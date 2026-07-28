# IdP 자격증명 부재 — 부팅은 성공하고 OIDC 라우트만 시끄럽게 실패한다 (#163: 강등의 대가가 어디로 옮겼는가)
import logging
import os
import subprocess
import sys
from collections.abc import Iterator
from pathlib import Path

import httpx
import pytest

from src.auth.oidc import Provider
from tests.conftest import API_ROOT

KAKAO_ENV = ("KAKAO_CLIENT_ID", "KAKAO_CLIENT_SECRET")
GOOGLE_ENV = ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET")

# env 이름 → Settings 필드. 전제 단언이 무엇을 봐야 하는지 여기서만 안다.
FIELD_OF_ENV = {
    "KAKAO_CLIENT_ID": "kakao_client_id",
    "KAKAO_CLIENT_SECRET": "kakao_client_secret",
    "GOOGLE_CLIENT_ID": "google_client_id",
    "GOOGLE_CLIENT_SECRET": "google_client_secret",
}


def _clear_caches() -> None:
    """자격증명을 읽는 lru_cache 둘 — settings만 비우면 oauth가 옛 값에 묶인 채 남는다(conftest 선례)."""
    from src.auth.oidc import get_oauth
    from src.core.config import get_settings

    get_settings.cache_clear()
    get_oauth.cache_clear()


def _without(monkeypatch: pytest.MonkeyPatch, keys: tuple[str, ...]) -> Iterator[None]:
    from src.core.config import get_settings

    for key in keys:
        monkeypatch.delenv(key, raising=False)
    _clear_caches()

    # 전제 단언 — 로컬 .env.local이 자격증명을 공급하면 조용히 통과하는 대신 여기서 깨진다.
    settings = get_settings()
    supplied = [key for key in keys if getattr(settings, FIELD_OF_ENV[key]) is not None]
    assert not supplied, (
        f".env.local이 {supplied}를 공급한다 — 이 테스트는 부재를 전제한다"
    )

    yield
    # monkeypatch가 env를 되돌린 뒤 다음 테스트가 다시 짓도록 캐시를 또 비운다.
    _clear_caches()


@pytest.fixture
def without_idp_credentials(
    migrated_db: str, monkeypatch: pytest.MonkeyPatch
) -> Iterator[None]:
    """자격증명 4개가 전부 없는 상태 — 배포 직후 flip 환경이 정확히 이 모양이다."""
    yield from _without(monkeypatch, KAKAO_ENV + GOOGLE_ENV)


@pytest.fixture
def without_google_credentials(
    migrated_db: str, monkeypatch: pytest.MonkeyPatch
) -> Iterator[None]:
    """한쪽만 없는 상태 — 한 provider의 부재가 다른 provider를 오염시키는지 본다."""
    yield from _without(monkeypatch, GOOGLE_ENV)


def test_app_imports_without_idp_credentials(tmp_path: Path) -> None:
    """AC: 자격증명 없이 앱 import·부팅이 성공한다 — 배포가 IdP 콘솔 등록(#100)에 묶이지 않는다.

    cwd를 빈 디렉토리로 두어 .env.local(상대경로)이 원천적으로 안 잡히게 한다 — 개발자 머신의
    로컬 정본과 무관하게 성립해야 하는 주장이다. 서브프로세스 관용구는 test_contract.py 선례.
    """
    env = {key: value for key, value in os.environ.items() if key not in FIELD_OF_ENV}
    env["PYTHONPATH"] = str(API_ROOT)
    env["DATABASE_URL"] = "postgresql+asyncpg://boot-check/placeholder"
    env["SESSION_SECRET"] = "boot-check-session-secret"
    env["GEMINI_API_KEY"] = "boot-check-gemini-key"

    result = subprocess.run(
        [sys.executable, "-c", "import src.main"],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr


@pytest.mark.usefixtures("without_idp_credentials")
async def test_login_without_credentials_fails_loudly(
    client: httpx.AsyncClient, caplog: pytest.LogCaptureFixture
) -> None:
    """AC: 조용한 500도 fail-open도 아니다 — 어떤 provider인지 응답에, 왜인지 로그에 남는다."""
    with caplog.at_level(logging.ERROR):
        res = await client.get(f"/api/v1/auth/{Provider.KAKAO.value}/login")

    assert res.status_code == 503, res.text
    assert Provider.KAKAO.value in res.json()["detail"]
    # 왜 — 누락된 env 이름은 서버 로그에만 (공개 URL에 설정 세부를 흘리지 않는다)
    assert all(key in caplog.text for key in KAKAO_ENV)


@pytest.mark.usefixtures("without_idp_credentials")
async def test_callback_without_credentials_is_not_a_user_auth_failure(
    client: httpx.AsyncClient,
) -> None:
    """서버 설정 결함이 사용자 인증 실패(401)로 흡수되면 원인이 사라진다 — 코드가 갈려야 한다."""
    res = await client.get(
        f"/api/v1/auth/{Provider.GOOGLE.value}/callback",
        params={"code": "irrelevant", "state": "irrelevant"},
    )

    assert res.status_code == 503, res.text
    assert Provider.GOOGLE.value in res.json()["detail"]


@pytest.fixture
def with_blank_kakao_credentials(
    migrated_db: str, monkeypatch: pytest.MonkeyPatch
) -> Iterator[None]:
    """변수는 있는데 값이 빈 상태 — 시크릿 바인딩이 실패했을 때 실제로 이렇게 온다."""
    for key in KAKAO_ENV:
        monkeypatch.setenv(key, "")
    _clear_caches()
    yield
    _clear_caches()


@pytest.mark.usefixtures("with_blank_kakao_credentials")
async def test_blank_credentials_are_absent_credentials(
    client: httpx.AsyncClient,
) -> None:
    """빈 값을 자격증명으로 인정하면 IdP까지 갔다가 남의 에러로 죽는다 — 부재와 같이 취급한다."""
    res = await client.get(f"/api/v1/auth/{Provider.KAKAO.value}/login")

    assert res.status_code == 503, res.text
    assert Provider.KAKAO.value in res.json()["detail"]


@pytest.mark.usefixtures("without_google_credentials", "idp")
async def test_configured_provider_survives_missing_peer(
    client: httpx.AsyncClient,
) -> None:
    """한 provider의 부재가 다른 provider를 죽이거나 남의 이름으로 실패하면 안 된다.

    레지스트리를 한 루프로 등록하던 구조에선 구글 시크릿 하나가 카카오 로그인까지 끌고 내려갔다.
    """
    kakao = await client.get(f"/api/v1/auth/{Provider.KAKAO.value}/login")
    google = await client.get(f"/api/v1/auth/{Provider.GOOGLE.value}/login")

    assert kakao.status_code == 302, kakao.text
    assert google.status_code == 503, google.text
    assert Provider.GOOGLE.value in google.json()["detail"]
