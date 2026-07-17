# 레시피 북 비즈니스 로직 — 저장 시 재료 추출 1회, 트랜잭션 경계. AsyncSession을 모른다 (backend.md §3)
from uuid import UUID

from src.llm.service import BaseLLMService
from src.recipes.exceptions import RecipeNotFound
from src.recipes.models import Recipe
from src.recipes.repository import RecipeBookRepository


class RecipeBookService:
    def __init__(self, recipes: RecipeBookRepository, llm: BaseLLMService) -> None:
        self._recipes = recipes
        self._llm = llm

    async def create(self, url: str, title: str) -> Recipe:
        """추출이 저장에 선행한다 — 실패하면 예외가 그대로 올라가 아무것도 저장되지 않는다.

        빈 목록은 실패가 아니다 — 프롬프트가 요리명 미인식 시 []를 정당하게 돌려준다. 그대로 저장한다.
        usage는 저장하지 않는다 — 원가 계측은 LLM 라우트(#101)의 응답 표면이지 레시피 북의 것이 아니다.
        """
        extraction = await self._llm.extract(title)
        recipe = await self._recipes.add(
            url=url, title=title, ingredients=extraction.ingredients
        )
        await self._recipes.commit()
        return recipe

    async def get(self, recipe_id: UUID) -> Recipe:
        recipe = await self._recipes.get(recipe_id)
        if recipe is None:
            raise RecipeNotFound
        return recipe

    async def update(
        self, recipe_id: UUID, *, title: str | None, ingredients: list[str] | None
    ) -> Recipe:
        """수정은 재추출하지 않는다 — 추출은 저장 시 1회뿐이고, 재료는 사용자가 직접 고친다."""
        recipe = await self.get(recipe_id)
        if title is not None:
            recipe.title = title
        if ingredients is not None:
            recipe.ingredients = ingredients  # 통째 교체 — 대입이라 변경 감지가 된다
        await self._recipes.commit()
        return recipe

    async def delete(self, recipe_id: UUID) -> None:
        recipe = await self.get(recipe_id)
        await self._recipes.delete(recipe)
        await self._recipes.commit()

    # list는 클래스 본문 마지막 — repository.py와 같은 이유(builtin list 가림 방지).
    async def list(self) -> list[Recipe]:
        return await self._recipes.list()
