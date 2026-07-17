# 로컬→계정 이전 비즈니스 로직 — 재추출 없는 원자적 bulk 등록. 트랜잭션 경계는 Service (backend.md §3)
#
# ⚠️ 시한부 모듈. 제거 트리거는 src/migration/ __init__.py 참조.
from collections.abc import Sequence

from sqlalchemy.exc import SQLAlchemyError

from src.migration.exceptions import RecipeImportFailed
from src.migration.schemas import RecipeImportItem
from src.recipes.models import Recipe
from src.recipes.repository import RecipeBookRepository


class RecipeImportService:
    """LLM seam을 **모른다** — 재료는 로컬에서 이미 추출됐고 그대로 저장한다. "등록 중 LLM 호출 0회"(AC)가
    테스트가 아니라 타입 수준에서 성립하는 이유다. recipes의 스코프드 Repository만 쓴다(§12.2 격리 재사용).
    """

    def __init__(self, recipes: RecipeBookRepository) -> None:
        self._recipes = recipes

    async def import_all(self, items: Sequence[RecipeImportItem]) -> list[Recipe]:
        """전량 성공 또는 전량 실패 — 항목마다 add(flush)하고 마지막에 1회 commit한다.

        중간 항목이 flush에서 실패하면 commit에 도달하지 못하고, 세션 컨텍스트 매니저가 트랜잭션을
        롤백해 저장 행이 0이 된다(recipes create의 추출 실패-미저장이 의존하는 같은 자동 롤백). 실패를
        RecipeImportFailed로 옮겨 라우터가 성공/실패를 명확히 구분하게 한다 — 부분 성공은 없다.
        """
        try:
            saved = [
                await self._recipes.add(
                    url=item.url, title=item.title, ingredients=item.ingredients
                )
                for item in items
            ]
            await self._recipes.commit()
        except SQLAlchemyError as exc:
            raise RecipeImportFailed from exc
        return saved
