# recipes DB 접근 전담 — 생성 시점에 owner로 스코프된다. 메서드는 owner를 인자로 받지 않는다 (backend.md §12.2)
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import col

from src.recipes.models import Recipe


class RecipeBookRepository:
    """호출자가 남의 행을 달라고 말할 방법 자체가 없다 — 관례가 아니라 구조다 (§12.2)."""

    def __init__(self, session: AsyncSession, owner_id: UUID) -> None:
        self._session = session
        self._owner_id = owner_id

    async def add(self, url: str, title: str, ingredients: list[str]) -> Recipe:
        # Recipe 조립은 여기서 한다 — owner_id를 밖에서 받는 순간 스코프가 뚫린다.
        recipe = Recipe(
            owner_id=self._owner_id, url=url, title=title, ingredients=ingredients
        )
        self._session.add(recipe)
        await self._session.flush()
        return recipe

    async def get(self, recipe_id: UUID) -> Recipe | None:
        result = await self._session.execute(
            select(Recipe).where(
                col(Recipe.id) == recipe_id,
                col(Recipe.owner_id) == self._owner_id,
            )
        )
        return result.scalar_one_or_none()

    async def delete(self, recipe: Recipe) -> None:
        await self._session.delete(recipe)

    async def commit(self) -> None:
        await self._session.commit()

    # list는 클래스 본문 **마지막**에 둔다 — 앞 메서드의 list[...] annotation은 클래스 스코프에서
    # 평가되므로, 이 이름이 먼저 바인딩되면 builtin list를 가려 import 시 TypeError로 터진다.
    async def list(self) -> list[Recipe]:
        result = await self._session.execute(
            select(Recipe)
            .where(col(Recipe.owner_id) == self._owner_id)
            # 삽입순 — 모바일 레시피 북 표시 순서와 패리티. 동률(같은 초 벌크 등록)은 id가 끊는다.
            .order_by(col(Recipe.created_at), col(Recipe.id))
        )
        return list(result.scalars().all())
