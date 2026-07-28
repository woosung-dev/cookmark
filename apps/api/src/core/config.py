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

    # IdP 자격증명 (#100). 카카오의 client_id는 콘솔의 REST API 키다 — id_token의 aud로도 돌아온다.
    # **필수에서 Optional로 강등됐다 (#163 · ADR-0012는 #162가 발행한다).** 필수였던 근거는 "로그인이 코어"(ADR-0009)였고,
    # 익명 기기 등록이 그 전제를 연기했다 — 그래서 IdP 콘솔 등록이 배포의 차단자에서 빠진다.
    # **조용한 로그인 장애 금지는 불변이고, 대가가 자리를 옮겼을 뿐이다** — 부재는 OIDC 라우트가 실제로
    # 불릴 때 503으로 시끄럽게 실패한다(src/auth/oidc.py·router.py). 부팅만 안 막는다.
    # **승격 트리거 — 넷 중 하나가 발화하면(둘째 기기 요구 · 재설치로 레시피 북 상실 · 코호트 20명 초과 ·
    # 공개 배포) 진짜 로그인이 필요해지고, 이 4필드를 다시 필수로 올린다.** 영구 결정이 아니다.
    kakao_client_id: str | None = None
    kakao_client_secret: SecretStr | None = None
    google_client_id: str | None = None
    google_client_secret: SecretStr | None = None
    # SessionMiddleware 서명 키 — OAuth state·nonce 운반 전용이고 우리 인증 세션과 무관하다(§9).
    session_secret: SecretStr

    # LLM 승계 (#101). 모델명은 환경설정 주입(스펙 #96) — 파일럿 중에는 바꾸지 않는다.
    # 단가는 USD per 1M 토큰 — 모델을 바꾸면 단가도 함께 바꿔야 원가 로그가 맞는다(_gemini.mjs 이식).
    gemini_api_key: SecretStr
    gemini_model: str = "gemini-3.1-flash-lite"
    gemini_price_input_per_m: float = 0.25
    gemini_price_output_per_m: float = 1.5

    @field_validator("cors_allowed_origins", mode="before")
    @classmethod
    def _split_comma_separated(cls, value: str | list[str]) -> list[str]:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @field_validator("cors_allowed_origins", mode="after")
    @classmethod
    def _reject_wildcard(cls, value: list[str]) -> list[str]:
        # 와일드카드 금지(§9.1)를 구조로 강제한다 — 쿠키 세션이라 allow_credentials가 켜져 있고,
        # Starlette은 그 조합에서 "*"를 요청 origin 반향으로 바꿔 조용히 아무 origin이나 통과시킨다.
        if "*" in value:
            raise ValueError(
                "CORS_ALLOWED_ORIGINS에 와일드카드를 쓸 수 없다 (backend.md §9.1)"
            )
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()  # 필수 필드는 env/.env.local이 공급한다
