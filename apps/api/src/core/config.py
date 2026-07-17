# 앱 설정 — pydantic-settings 기반. 비밀은 SecretStr, 로컬 정본은 .env.local (backend.md §9.1·§10)
from functools import lru_cache
from typing import Annotated

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env.local", env_file_encoding="utf-8")

    database_url: SecretStr
    # §10 함정 — list[str] env는 JSON 선-디코드라 콤마 값이 크래시한다. NoDecode + validator 직접 파싱.
    # 기본 빈 목록 — CORS는 필요한 환경에서만 켠다. 와일드카드·하드코딩 금지 (§9.1).
    cors_allowed_origins: Annotated[list[str], NoDecode] = []

    @field_validator("cors_allowed_origins", mode="before")
    @classmethod
    def _split_comma_separated(cls, value: str | list[str]) -> list[str]:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()  # 필수 필드는 env/.env.local이 공급한다
