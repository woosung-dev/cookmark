# 테스트 공용 픽스처 — testcontainers 실 Postgres에 alembic 적용 후 ASGI 클라이언트 제공 (스펙 #96: DB는 seam이 아니다)
import os
from collections.abc import AsyncIterator, Iterator
from pathlib import Path

import httpx
import pytest
from alembic import command
from alembic.config import Config
from testcontainers.postgres import PostgresContainer

# 테스트 전용 허용 origin — 앱 코드가 아니라 env로 주입된다 (하드코딩 금지 AC의 검증 데이터)
ALLOWED_ORIGIN = "http://localhost:5566"

API_ROOT = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="session")
def database_url() -> Iterator[str]:
    """실 Postgres 컨테이너를 띄우고 앱 설정을 env로 주입한다."""
    with PostgresContainer("postgres:17-alpine", driver="asyncpg") as pg:
        url = pg.get_connection_url()
        os.environ["DATABASE_URL"] = url
        os.environ["CORS_ALLOWED_ORIGINS"] = ALLOWED_ORIGIN

        from src.common.database import get_engine, get_sessionmaker
        from src.core.config import get_settings

        # 세 캐시 전부 클리어 — settings만 지우면 engine이 이전 URL(.env.local)에 묶인 채 남는다
        get_settings.cache_clear()
        get_engine.cache_clear()
        get_sessionmaker.cache_clear()
        yield url


@pytest.fixture(scope="session")
def migrated_db(database_url: str) -> str:
    """컨테이너 실 DB에 alembic upgrade head를 적용한다 (AC: 실 DB 적용 증명)."""
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "alembic"))
    command.upgrade(config, "head")
    return database_url


@pytest.fixture
async def client(migrated_db: str) -> AsyncIterator[httpx.AsyncClient]:
    """ASGI 관통 클라이언트 — sync TestClient 금지 (backend.md §10)."""
    from src.main import app

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport, base_url="http://testserver"
    ) as ac:
        yield ac
