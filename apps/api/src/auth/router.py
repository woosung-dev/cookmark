# auth 라우터 — HTTP 전용. OIDC 왕복은 oidc.py에, 계정·세션 로직은 service.py에 위임한다 (backend.md §3)
import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from starlette.responses import RedirectResponse

from src.auth import oidc
from src.auth.dependencies import (
    SESSION_COOKIE,
    UNAUTHORIZED,
    CurrentAccount,
    extract_session_token,
    get_auth_service,
)
from src.auth.exceptions import IdentityUnavailable, ProviderNotConfigured
from src.auth.oidc import Provider
from src.auth.schemas import AccountResponse, SessionResponse
from src.auth.service import SESSION_TTL, AuthService

router = APIRouter(prefix="/auth", tags=["auth"])

Service = Annotated[AuthService, Depends(get_auth_service)]

logger = logging.getLogger(__name__)

# 503은 IdP 자격증명이 없을 때 이 두 라우트가 실제로 내는 응답이다 — 문서화해야 생성된 계약이
# 구현과 어긋나지 않는다(#99). 401(사용자 인증 실패)과 코드가 갈리는 것이 요점이다(#163).
UNCONFIGURED: dict[int | str, dict[str, str]] = {
    503: {"description": "해당 IdP의 자격증명이 이 서버에 설정되지 않았다"}
}


def _unconfigured(exc: ProviderNotConfigured) -> HTTPException:
    """설정 결함을 시끄럽게 만든다 — 어떤 provider인지는 응답에, 왜인지는 로그에 (#163).

    누락된 env 이름을 본문에 싣지 않는 이유는 이 라우트가 공개 URL이기 때문이다. 운영자는 같은
    사건의 로그 한 줄에서 이름까지 본다.
    """
    logger.error(
        "IdP 자격증명 부재 — provider=%s 미설정=%s",
        exc.provider,
        ", ".join(exc.missing),
    )
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=f"{exc.provider} 로그인이 이 서버에 설정되지 않았다",
    )


# 쿠키 속성은 §9 고정 — HttpOnly(스크립트 차단)·Secure(평문 전송 차단)·Lax(cross-site 전송 차단).
# 브라우저는 localhost를 보안 컨텍스트로 취급하므로 Secure가 로컬 http 데모를 막지 않는다.
# 세팅과 삭제가 같은 속성을 써야 브라우저가 같은 쿠키로 알아본다 — 그래서 둘을 나란히 둔다.


def _set_session_cookie(response: Response, token: str) -> None:
    response.set_cookie(
        SESSION_COOKIE,
        token,
        max_age=int(SESSION_TTL.total_seconds()),
        path="/",
        httponly=True,
        secure=True,
        samesite="lax",
    )


def _clear_session_cookie(response: Response) -> None:
    response.delete_cookie(
        SESSION_COOKIE, path="/", httponly=True, secure=True, samesite="lax"
    )


@router.get(
    "/{provider}/login",
    status_code=status.HTTP_302_FOUND,
    response_class=RedirectResponse,
    responses={302: {"description": "IdP 인가 화면으로 리다이렉트"}, **UNCONFIGURED},
)
async def start_login(provider: Provider, request: Request) -> RedirectResponse:
    """IdP 인가 화면으로 보낸다. redirect_uri는 라우트에서 도출해 설정 없이 성립시킨다."""
    redirect_uri = str(request.url_for("auth_callback", provider=provider.value))
    try:
        return await oidc.start_login(provider, request, redirect_uri)
    except ProviderNotConfigured as exc:
        raise _unconfigured(exc) from exc


@router.get(
    "/{provider}/callback",
    name="auth_callback",
    responses={**UNAUTHORIZED, **UNCONFIGURED},
)
async def auth_callback(
    provider: Provider,
    request: Request,
    response: Response,
    service: Service,
) -> SessionResponse:
    """IdP가 돌려보낸 코드를 검증된 신원으로 바꾸고 세션을 발급한다."""
    try:
        identity = await oidc.fetch_identity(provider, request)
    except ProviderNotConfigured as exc:
        # 401과 별개로 잡는다 — 서버 설정 결함이 사용자 인증 실패로 흡수되면 원인이 사라진다(#163).
        raise _unconfigured(exc) from exc
    except IdentityUnavailable as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="로그인에 실패했다"
        ) from exc

    issued = await service.login(identity.iss, identity.sub)
    _set_session_cookie(response, issued.token)
    return SessionResponse(
        token=issued.token,
        expires_at=issued.expires_at,
        account=AccountResponse.model_validate(issued.account),
    )


@router.get("/me", responses=UNAUTHORIZED)
async def read_current_account(account: CurrentAccount) -> AccountResponse:
    """세션 검증 표면이자 로그인 데모 지점."""
    return AccountResponse.model_validate(account)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(request: Request, response: Response, service: Service) -> None:
    """제시된 증표를 파기한다. 이미 죽은 증표로 불러도 결과는 같으므로 멱등이다."""
    token = extract_session_token(request)
    if token is not None:
        await service.logout(token)
    _clear_session_cookie(response)


@router.delete(
    "/account", status_code=status.HTTP_204_NO_CONTENT, responses=UNAUTHORIZED
)
async def withdraw(
    account: CurrentAccount, response: Response, service: Service
) -> None:
    """탈퇴 — 계정·세션 즉시 하드 삭제. 지울 대상은 세션에서 나오지 클라이언트가 대지 않는다."""
    await service.withdraw(account)
    _clear_session_cookie(response)
