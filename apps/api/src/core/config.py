# 앱 설정 — pydantic-settings 기반. 비밀은 SecretStr, 로컬 정본은 .env.local (backend.md §9.1·§10)
from functools import lru_cache
from typing import Annotated

from pydantic import Field, SecretStr, field_validator
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

    # 익명 기기 등록의 문지기 (#167 · ADR-0012). LLM 라우트의 세션 필수(무세션 401)가 공개 URL의
    # 비용 표면을 닫고 있었는데 익명 등록이 그 장치를 무효화한다 — 이 키가 다시 닫는다.
    # **필드명과 env명이 갈리므로 alias로 못박는다** — 같은 값이 APK의 dart-define으로도 살아서
    # 이름을 앱과 공유해야 한다(`COOKMARK_SERVER_BASE`와 같은 접두사 관례, #164).
    # 위협 모델은 "URL을 찍어보는 스캐너"이지 "APK를 리버싱하는 공격자"가 아니다 — 그래서 레이트
    # 리밋도 계정당 쿼터도 없다(ADR-0012). 회전은 등록에만 영향하고 기존 세션은 불변이다.
    register_key: SecretStr = Field(validation_alias="COOKMARK_REGISTER_KEY")

    # LLM 승계 (#101). 모델명은 환경설정 주입(스펙 #96) — 파일럿 중에는 바꾸지 않는다.
    # 단가는 USD per 1M 토큰 — 모델을 바꾸면 단가도 함께 바꿔야 원가 로그가 맞는다(_gemini.mjs 이식).
    gemini_api_key: SecretStr
    gemini_model: str = "gemini-3.1-flash-lite"
    gemini_price_input_per_m: float = 0.25
    gemini_price_output_per_m: float = 1.5

    @field_validator("register_key", mode="after")
    @classmethod
    def _reject_blank_register_key(cls, value: SecretStr) -> SecretStr:
        # **빈 값도 부재다** (#163의 함정, src/auth/oidc.py의 _is_blank와 같은 판정).
        # `COOKMARK_REGISTER_KEY=`를 주면 pydantic이 ''로 채우는데, 그러면 등록 키 비교가 빈
        # 문자열끼리 성립해 **등록이 통째로 열린다**. 시크릿 바인딩 실패의 실제 모양이 이것이라
        # 조용히 열리는 대신 부팅에서 시끄럽게 죽인다.
        if not value.get_secret_value().strip():
            raise ValueError(
                "COOKMARK_REGISTER_KEY가 비어 있다 — 익명 등록이 통째로 열린다"
            )
        return value

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
