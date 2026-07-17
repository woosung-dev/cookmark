# Alembic 마이그레이션 환경 — URL은 앱 Settings에서 온다 (env var 우선이라 테스트·CI가 주입 가능)
import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.engine import Connection
from sqlmodel import SQLModel

import src.auth.models  # noqa: F401 — import해야 테이블이 metadata에 등록된다 (누락은 조용하다)
from src.common.database import get_engine
from src.core.config import get_settings

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# autogenerate·drift 비교의 기준. 새 테이블을 만든 모듈은 위에 import를 추가해야 한다 —
# 빠뜨리면 "no changes detected"로 조용히 지나가고 `alembic check`도 통과한다.
target_metadata = SQLModel.metadata


def run_migrations_offline() -> None:
    """--sql dry-run (backend.md 검증 앵커) — DB 연결 없이 SQL만 출력한다."""
    context.configure(
        url=get_settings().database_url.get_secret_value(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)

    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    # 앱과 같은 engine 정의를 재사용 — statement_cache_size=0 등 connect_args가 한 곳에 산다.
    engine = get_engine()

    # 이 함수는 asyncio.run이 만든 자기 루프에서 돈다. engine은 lru_cache라 풀에 다른 루프에서
    # 만든 커넥션이 남아 있을 수 있고(예: pytest-asyncio 세션 루프에서 앱이 쓰던 것), 그걸
    # 재사용하면 asyncpg가 "attached to a different loop"로 터진다. close=False로 풀만 버린다 —
    # 그 커넥션들은 남의 루프 소유라 여기서 닫을 수 없고, 닫으려 드는 순간 같은 이유로 터진다.
    await engine.dispose(close=False)

    async with engine.connect() as connection:
        await connection.run_sync(do_run_migrations)

    # 대칭으로 뒷정리 — 여기서 만든 커넥션이 풀에 남으면 이번엔 반대 방향으로(다음 루프가
    # 이걸 재사용하다) 같은 폭발이 난다. 이쪽은 우리 루프 소유라 정상적으로 닫는다.
    await engine.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
