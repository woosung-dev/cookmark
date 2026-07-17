# Depends() 조립 — 검증된 세션에서 owner를 꺼내 스코프드 repo로 이전 서비스를 만든다 (backend.md §12.2)
#
# ⚠️ 시한부 모듈. 제거 트리거는 src/migration/ __init__.py 참조.
from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from src.auth.dependencies import CurrentAccount
from src.common.database import get_async_session
from src.migration.service import RecipeImportService
from src.recipes.repository import RecipeBookRepository


def get_recipe_import_service(
    session: Annotated[AsyncSession, Depends(get_async_session)],
    account: CurrentAccount,
) -> RecipeImportService:
    # owner_id는 서버가 검증한 세션에서만 나온다 — 클라이언트가 대는 경로는 없다 (§9).
    # LLM은 주입하지 않는다 — 이전은 재추출을 하지 않으므로 서비스가 seam을 알 필요가 없다(AC: LLM 0회).
    return RecipeImportService(RecipeBookRepository(session, owner_id=account.id))
