# DB 배선 단일 정의 — AsyncEngine·async_sessionmaker. AsyncSession은 Repository만 보유한다 (backend.md §3)
from collections.abc import AsyncIterator
from functools import lru_cache

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from src.core.config import get_settings


@lru_cache
def get_engine() -> AsyncEngine:
    # Neon PgBouncer 경유 대비 statement_cache_size=0 필수 (ADR-0009 · 조사 #82 함정)
    return create_async_engine(
        get_settings().database_url.get_secret_value(),
        connect_args={"statement_cache_size": 0},
    )


@lru_cache
def get_sessionmaker() -> async_sessionmaker[AsyncSession]:
    # expire_on_commit=False — 비동기에서 commit 후 재접근 시 암묵 lazy load 방지 (backend.md §10).
    # **#167 이후로는 편의가 아니라 정합성 요건이다** — 슬라이딩 갱신이 요청 스코프 세션을 의존성
    # 단계에서 커밋하므로, True로 뒤집으면 라우트 본문의 첫 account.id 접근이 greenlet 밖 lazy
    # refresh를 일으켜 MissingGreenlet으로 죽는다.
    return async_sessionmaker(get_engine(), expire_on_commit=False)


async def get_async_session() -> AsyncIterator[AsyncSession]:
    async with get_sessionmaker()() as session:
        yield session
