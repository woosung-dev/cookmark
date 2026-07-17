# OIDC IdP 경계 — 앱의 아웃바운드 IdP 왕복은 전부 여기를 지난다 (스펙 #96: 페이크 주입 seam ②)
from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from typing import Any

from authlib.common.errors import AuthlibBaseError
from authlib.integrations.starlette_client import OAuth
from fastapi import Request
from joserfc.errors import JoseError
from starlette.responses import RedirectResponse

from src.auth.exceptions import IdentityUnavailable
from src.core.config import Settings, get_settings

# scope에 리터럴 "openid"가 없으면 authlib이 nonce를 저장하지 않고, nonce가 없으면 id_token 검증을
# 통째로 건너뛴다(fail-open). 카카오는 콘솔 토글만 켜져 있으면 scope와 무관하게 id_token을 주므로
# 이 상수가 빠지면 "에러 없이 미검증 토큰"을 쥐게 된다. 설정으로 빼지 않는 이유가 이것이다.
SCOPE = "openid"
DISCOVERY_PATH = "/.well-known/openid-configuration"


class Provider(StrEnum):
    KAKAO = "kakao"
    GOOGLE = "google"


@dataclass(frozen=True)
class ProviderConfig:
    issuer: str
    # authlib은 서버 메타데이터의 token_endpoint_auth_methods_supported를 읽지 않는다 — 기본은
    # client_secret_basic이고, 카카오는 client_secret_post만 광고하므로 명시해야 한다(#77).
    token_endpoint_auth_method: str | None


PROVIDERS: dict[Provider, ProviderConfig] = {
    Provider.KAKAO: ProviderConfig(
        issuer="https://kauth.kakao.com",
        token_endpoint_auth_method="client_secret_post",
    ),
    Provider.GOOGLE: ProviderConfig(
        issuer="https://accounts.google.com",
        token_endpoint_auth_method=None,
    ),
}


@dataclass(frozen=True)
class Identity:
    """IdP가 서명으로 보증한 신원. 우리가 계정 키로 쓰는 값이 정확히 이 둘이다."""

    iss: str
    sub: str


def _credentials(provider: Provider, settings: Settings) -> tuple[str, str]:
    match provider:
        case Provider.KAKAO:
            return (
                settings.kakao_client_id,
                settings.kakao_client_secret.get_secret_value(),
            )
        case Provider.GOOGLE:
            return (
                settings.google_client_id,
                settings.google_client_secret.get_secret_value(),
            )


@lru_cache
def get_oauth() -> OAuth:
    """authlib 레지스트리. 지연 생성이라 설정이 갖춰진 뒤에 자격증명을 읽는다."""
    settings = get_settings()
    oauth = OAuth()
    for provider, config in PROVIDERS.items():
        client_id, client_secret = _credentials(provider, settings)
        client_kwargs: dict[str, str] = {"scope": SCOPE}
        if config.token_endpoint_auth_method is not None:
            client_kwargs["token_endpoint_auth_method"] = (
                config.token_endpoint_auth_method
            )
        # 미인식 kwarg는 조용히 server_metadata로 흡수된다 — 키 이름 오타가 에러를 안 내니 주의.
        oauth.register(
            name=provider.value,
            client_id=client_id,
            client_secret=client_secret,
            server_metadata_url=f"{config.issuer}{DISCOVERY_PATH}",
            client_kwargs=client_kwargs,
        )
    return oauth


async def start_login(
    provider: Provider, request: Request, redirect_uri: str
) -> RedirectResponse:
    """IdP 인가 화면으로 302. state·nonce는 authlib이 만들어 서명 쿠키(SessionMiddleware)에 맡긴다."""
    client = get_oauth().create_client(provider.value)
    response: RedirectResponse = await client.authorize_redirect(request, redirect_uri)
    return response


async def fetch_identity(provider: Provider, request: Request) -> Identity:
    """인가 코드를 ID 토큰으로 바꾸고 검증된 신원만 돌려준다. 토큰 자체는 여기서 죽는다(§9: 1회 검증 후 폐기)."""
    client = get_oauth().create_client(provider.value)
    try:
        token: dict[str, Any] = await client.authorize_access_token(request)
    except (AuthlibBaseError, JoseError) as exc:
        raise IdentityUnavailable(str(exc)) from exc

    # userinfo는 authlib이 id_token을 실제로 검증했을 때만 채워진다. 없으면 검증이 돌지 않았다는
    # 뜻이므로 절대 소프트 폴백하지 않는다 — 그 폴백이 곧 인증 우회다.
    claims = token.get("userinfo")
    if claims is None:
        raise IdentityUnavailable("IdP가 검증 가능한 ID 토큰을 주지 않았다")

    iss, sub = claims.get("iss"), claims.get("sub")
    if not iss or not sub:
        raise IdentityUnavailable("ID 토큰에 iss 또는 sub가 없다")
    return Identity(iss=str(iss), sub=str(sub))
