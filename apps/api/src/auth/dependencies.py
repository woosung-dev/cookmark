# Depends() 조립 + 세션 검증 — 증표를 계정으로 바꾸는 로직은 이 모듈에만 산다 (backend.md §9)
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from src.auth.models import Account
from src.auth.repository import AccountRepository, SessionRepository
from src.auth.service import AuthService
from src.common.database import get_async_session

SESSION_COOKIE = "cookmark_session"
_BEARER_PREFIX = "bearer "


def get_auth_service(
    session: Annotated[AsyncSession, Depends(get_async_session)],
) -> AuthService:
    # 두 Repository가 같은 session을 공유한다 — 트랜잭션 경계는 서비스가 정한다 (§3).
    return AuthService(AccountRepository(session), SessionRepository(session))


def extract_session_token(request: Request) -> str | None:
    """저장은 하나, 운반만 플랫폼별이다 — 네이티브는 Bearer, 웹은 쿠키. 토큰은 같은 값이다 (§9).

    Authorization 헤더가 쿠키를 이긴다 — 명시가 암묵을 이긴다.
    """
    header = request.headers.get("authorization")
    if header and header.lower().startswith(_BEARER_PREFIX):
        return header[len(_BEARER_PREFIX) :].strip() or None
    return request.cookies.get(SESSION_COOKIE)


async def get_current_account(
    request: Request,
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> Account:
    """현재 계정은 서버가 검증한 세션에서만 나온다 — 클라이언트가 계정 id를 대는 경로는 없다 (§9)."""
    token = extract_session_token(request)
    account = await service.authenticate(token) if token else None
    if account is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="세션이 없거나 유효하지 않다",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return account


CurrentAccount = Annotated[Account, Depends(get_current_account)]
