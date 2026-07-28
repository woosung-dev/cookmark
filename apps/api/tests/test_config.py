# Settings 순수 로직 유닛 — CORS 콤마 파싱·기본 빈 목록 (backend.md §10 함정 회귀 방지) · IdP 강등 (#163)
import pytest

from src.core.config import Settings

# 강등 후에도 필수로 남는 필드 (#163: 강등 대상은 IdP 4개뿐이다)
REQUIRED_ENV = {
    "DATABASE_URL": "postgresql+asyncpg://unit-test",
    "SESSION_SECRET": "unit-test-session-secret",
    "GEMINI_API_KEY": "unit-test-gemini-key",
}

IDP_ENV = (
    "KAKAO_CLIENT_ID",
    "KAKAO_CLIENT_SECRET",
    "GOOGLE_CLIENT_ID",
    "GOOGLE_CLIENT_SECRET",
)


@pytest.fixture
def isolated_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """이 파일의 테스트를 프로세스 env에서 떼어낸다 — 앞선 테스트가 흘린 값에 기대지 않는다.

    이전엔 알파벳순으로 앞선 test_auth_login.py가 session 픽스처로 os.environ에 흘려놓은
    IdP·세션·Gemini 값 덕에 통과했고, 이 파일만 단독 실행하면 ValidationError로 죽었다(#163).
    """
    for key, value in REQUIRED_ENV.items():
        monkeypatch.setenv(key, value)
    for key in IDP_ENV:
        monkeypatch.delenv(key, raising=False)


@pytest.mark.usefixtures("isolated_env")
def test_idp_credentials_are_optional() -> None:
    """AC: 자격증명 4개가 없어도 설정이 성립한다 — 부팅이 IdP 콘솔 등록(#100)에 묶이지 않는다."""
    settings = Settings(_env_file=None)

    assert settings.kakao_client_id is None
    assert settings.kakao_client_secret is None
    assert settings.google_client_id is None
    assert settings.google_client_secret is None


@pytest.mark.usefixtures("isolated_env")
def test_cors_env_comma_separated_is_parsed(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv(
        "CORS_ALLOWED_ORIGINS", "http://localhost:5566, http://localhost:7777"
    )

    settings = Settings(_env_file=None)

    assert settings.cors_allowed_origins == [
        "http://localhost:5566",
        "http://localhost:7777",
    ]


@pytest.mark.usefixtures("isolated_env")
def test_cors_defaults_to_empty_list(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("CORS_ALLOWED_ORIGINS", raising=False)

    settings = Settings(_env_file=None)

    assert settings.cors_allowed_origins == []
