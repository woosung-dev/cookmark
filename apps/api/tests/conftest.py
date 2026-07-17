# 테스트 공용 픽스처 — testcontainers 실 Postgres에 alembic 적용 후 ASGI 클라이언트 제공 (스펙 #96: DB는 seam이 아니다)
import os
from collections.abc import AsyncIterator, Iterator
from pathlib import Path

import httpx
import pytest
import respx
from alembic import command
from alembic.config import Config
from sqlalchemy.ext.asyncio import AsyncSession
from testcontainers.postgres import PostgresContainer

from src.auth.oidc import Provider
from tests.idp import CLIENT_IDS, FakeIdp

# 테스트 전용 허용 origin — 앱 코드가 아니라 env로 주입된다 (하드코딩 금지 AC의 검증 데이터)
ALLOWED_ORIGIN = "http://localhost:5566"

API_ROOT = Path(__file__).resolve().parent.parent

# main.py는 **import 시점에** 허용 목록을 CORS 미들웨어에 바인딩한다 — 그래서 이 값은 어떤 테스트가
# 앱을 먼저 import하든 이미 박혀 있어야 한다(픽스처 안에서 넣으면 앱을 먼저 import한 테스트가 빈 목록으로
# 굳혀버린다). conftest는 테스트 모듈보다 먼저 import되므로 여기가 그 유일한 지점이다.
os.environ["CORS_ALLOWED_ORIGINS"] = ALLOWED_ORIGIN


@pytest.fixture(scope="session")
def database_url() -> Iterator[str]:
    """실 Postgres 컨테이너를 띄우고 앱 설정을 env로 주입한다."""
    with PostgresContainer("postgres:17-alpine", driver="asyncpg") as pg:
        url = pg.get_connection_url()
        os.environ["DATABASE_URL"] = url
        # CORS는 #99가 모듈 스코프로 옮겼다(위) — 여기서 다시 세팅하지 않는다.
        # IdP 자격증명은 가짜 IdP(tests/idp.py)와 짝이다 — id_token의 aud가 여기 client_id와 맞아야 검증을 통과한다.
        os.environ["KAKAO_CLIENT_ID"] = CLIENT_IDS[Provider.KAKAO]
        os.environ["KAKAO_CLIENT_SECRET"] = "test-kakao-secret"
        os.environ["GOOGLE_CLIENT_ID"] = CLIENT_IDS[Provider.GOOGLE]
        os.environ["GOOGLE_CLIENT_SECRET"] = "test-google-secret"
        os.environ["SESSION_SECRET"] = "test-session-secret-0123456789abcdef"

        from src.auth.oidc import get_oauth
        from src.common.database import get_engine, get_sessionmaker
        from src.core.config import get_settings

        # 캐시 전부 클리어 — settings만 지우면 engine·oauth가 이전 값(.env.local)에 묶인 채 남는다
        get_settings.cache_clear()
        get_engine.cache_clear()
        get_sessionmaker.cache_clear()
        get_oauth.cache_clear()
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
    """ASGI 관통 클라이언트 — sync TestClient 금지 (backend.md §10).

    base_url이 https인 이유 — 세션 쿠키는 Secure라 http 요청엔 되돌아오지 않는다(RFC 6265).
    ASGITransport는 스킴을 신경쓰지 않으므로 https가 prod에 더 가깝기도 하다.
    """
    from src.main import app

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport, base_url="https://testserver"
    ) as ac:
        yield ac


@pytest.fixture
def idp() -> Iterator[FakeIdp]:
    """카카오·구글 실 URL을 가로채는 가짜 IdP. respx는 ASGITransport를 통과시킨다(실측 확인)."""
    with respx.mock(assert_all_called=False) as router:
        yield FakeIdp(router)


@pytest.fixture
async def db_session(migrated_db: str) -> AsyncIterator[AsyncSession]:
    """테스트가 DB 최종 상태를 직접 확인할 때 쓰는 세션 — 앱과 같은 sessionmaker."""
    from src.common.database import get_sessionmaker

    async with get_sessionmaker()() as session:
        yield session
