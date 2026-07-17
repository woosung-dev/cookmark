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
    # expire_on_commit=False — 비동기에서 commit 후 재접근 시 암묵 lazy load 방지 (backend.md §10)
    return async_sessionmaker(get_engine(), expire_on_commit=False)


async def get_async_session() -> AsyncIterator[AsyncSession]:
    async with get_sessionmaker()() as session:
        yield session
