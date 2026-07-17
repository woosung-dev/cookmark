# Alembic 마이그레이션 환경 — URL은 앱 Settings에서 온다 (env var 우선이라 테스트·CI가 주입 가능)
import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.engine import Connection

from src.common.database import get_engine
from src.core.config import get_settings

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# 모델이 아직 없다 — 테이블 도입 티켓(#100·#103)에서 SQLModel.metadata로 교체해 autogenerate를 배선하고,
# 그때 backend.md §2의 `uv run alembic check`를 검증 앵커(CI 포함)에 복원한다(metadata 없인 무의미).
target_metadata = None


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

    async with engine.connect() as connection:
        await connection.run_sync(do_run_migrations)

    # dispose 필수 — asyncio.run 루프에서 만든 커넥션이 풀에 남으면
    # 이후 다른 루프(pytest-asyncio 세션 루프)가 재사용하다 asyncpg가 폭발한다.
    await engine.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
