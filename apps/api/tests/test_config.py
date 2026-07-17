# Settings 순수 로직 유닛 — CORS 콤마 파싱·기본 빈 목록 (backend.md §10 함정 회귀 방지)
import pytest

from src.core.config import Settings


def test_cors_env_comma_separated_is_parsed(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+asyncpg://unit-test")
    monkeypatch.setenv(
        "CORS_ALLOWED_ORIGINS", "http://localhost:5566, http://localhost:7777"
    )

    settings = Settings(_env_file=None)

    assert settings.cors_allowed_origins == [
        "http://localhost:5566",
        "http://localhost:7777",
    ]


def test_cors_defaults_to_empty_list(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+asyncpg://unit-test")
    monkeypatch.delenv("CORS_ALLOWED_ORIGINS", raising=False)

    settings = Settings(_env_file=None)

    assert settings.cors_allowed_origins == []
