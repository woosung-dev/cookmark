# Depends() 조립 — 검증된 세션에서 owner를 꺼내 Repository를 생성 시점에 스코프한다 (backend.md §12.2)
from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from src.auth.dependencies import CurrentAccount
from src.common.database import get_async_session
from src.llm.dependencies import get_llm_service
from src.llm.service import BaseLLMService
from src.recipes.repository import RecipeBookRepository
from src.recipes.service import RecipeBookService


def get_recipe_book_service(
    session: Annotated[AsyncSession, Depends(get_async_session)],
    account: CurrentAccount,
    llm: Annotated[BaseLLMService, Depends(get_llm_service)],
) -> RecipeBookService:
    # owner_id는 서버가 검증한 세션에서만 나온다 — 클라이언트가 대는 경로는 없다 (§9).
    # get_async_session은 요청당 캐시라 auth 검증과 이 repo가 같은 session을 쓴다 (§3).
    return RecipeBookService(RecipeBookRepository(session, owner_id=account.id), llm)
