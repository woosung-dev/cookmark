# OIDC IdP 경계 — 앱의 아웃바운드 IdP 왕복은 전부 여기를 지난다 (스펙 #96: 페이크 주입 seam ②)
from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from typing import Any

from authlib.common.errors import AuthlibBaseError
from authlib.integrations.starlette_client import OAuth
from fastapi import Request
from joserfc.errors import JoseError
from pydantic import SecretStr
from starlette.responses import RedirectResponse

from src.auth.exceptions import IdentityUnavailable, ProviderNotConfigured
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


# (env 이름, 값) 두 쌍. 이름을 값과 함께 드는 이유는 부재를 보고할 때다 (#163) — 운영자가 봐야 하는
# 건 설정 필드명이 아니라 자기가 주입하지 않은 변수의 이름이다.
_CredentialPairs = tuple[tuple[str, str | None], tuple[str, SecretStr | None]]


def _credential_pairs(provider: Provider, settings: Settings) -> _CredentialPairs:
    """자격증명이 설정의 어느 필드에서 오는지 아는 유일한 자리."""
    match provider:
        case Provider.KAKAO:
            return (
                ("KAKAO_CLIENT_ID", settings.kakao_client_id),
                ("KAKAO_CLIENT_SECRET", settings.kakao_client_secret),
            )
        case Provider.GOOGLE:
            return (
                ("GOOGLE_CLIENT_ID", settings.google_client_id),
                ("GOOGLE_CLIENT_SECRET", settings.google_client_secret),
            )


def _is_blank(value: str | SecretStr | None) -> bool:
    """미설정 판정 — **빈 값도 부재다** (#163).

    강등 이후 "변수가 없거나 비어 있음"이 정상 상태가 됐고, 시크릿 바인딩이 빈 문자열을 주는 것은
    실제 배포 실패 모드다. 빈 값을 자격증명으로 인정하면 authlib이 빈 client_id로 등록에 성공해
    IdP까지 갔다가 남의 에러로 죽는다 — 이 함수가 막는 것이 정확히 그 조용한 로그인 장애다.
    """
    if value is None:
        return True
    raw = value.get_secret_value() if isinstance(value, SecretStr) else value
    return not raw.strip()


def _missing_credentials(pairs: _CredentialPairs) -> tuple[str, ...]:
    """누락된 자격증명 env 이름. 빈 튜플 = 설정됨 (#163: 부재 판정은 여기 하나뿐이다)."""
    return tuple(name for name, value in pairs if _is_blank(value))


def _credentials(provider: Provider, settings: Settings) -> tuple[str, str]:
    pairs = _credential_pairs(provider, settings)
    missing = _missing_credentials(pairs)
    if missing:
        raise ProviderNotConfigured(provider.value, missing)

    (_, client_id), (_, client_secret) = pairs
    # 위 가드가 None·빈 값을 전부 걸렀다 — 남은 건 실제 값뿐이라고 타입 체커에게도 말해준다.
    assert client_id is not None and client_secret is not None
    return client_id, client_secret.get_secret_value()


@lru_cache
def get_oauth() -> OAuth:
    """authlib 레지스트리. 지연 생성이라 설정이 갖춰진 뒤에 자격증명을 읽는다.

    자격증명이 없는 provider는 **등록하지 않고 건너뛴다** (#163). 한 루프가 둘을 함께 등록하므로
    여기서 걸러내지 않으면 한쪽의 부재가 다른 쪽 로그인까지 끌고 내려가고, 실패에 남의 이름이 붙는다.
    미등록의 대가는 아래 _client가 호출 시점에 시끄럽게 치른다.
    """
    settings = get_settings()
    oauth = OAuth()
    for provider, config in PROVIDERS.items():
        try:
            client_id, client_secret = _credentials(provider, settings)
        except ProviderNotConfigured:
            continue
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


def _client(provider: Provider) -> Any:
    """등록된 authlib 클라이언트. 미등록(자격증명 부재)이면 여기서 시끄럽게 죽는다 (#163).

    create_client는 미등록 이름에 None을 돌려준다 — 그대로 쓰면 AttributeError가 나고 원인 없는
    500이 된다. 그 조용한 경로를 닫는 것이 이 함수의 전부다.
    """
    client = get_oauth().create_client(provider.value)
    if client is None:
        raise ProviderNotConfigured(
            provider.value,
            _missing_credentials(_credential_pairs(provider, get_settings())),
        )
    return client


async def start_login(
    provider: Provider, request: Request, redirect_uri: str
) -> RedirectResponse:
    """IdP 인가 화면으로 302. state·nonce는 authlib이 만들어 서명 쿠키(SessionMiddleware)에 맡긴다."""
    response: RedirectResponse = await _client(provider).authorize_redirect(
        request, redirect_uri
    )
    return response


async def fetch_identity(provider: Provider, request: Request) -> Identity:
    """인가 코드를 ID 토큰으로 바꾸고 검증된 신원만 돌려준다. 토큰 자체는 여기서 죽는다(§9: 1회 검증 후 폐기)."""
    client = _client(provider)
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
