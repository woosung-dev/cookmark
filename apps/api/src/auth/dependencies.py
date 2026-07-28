# Depends() 조립 + 세션 검증 — 증표를 계정으로 바꾸는 로직은 이 모듈에만 산다 (backend.md §9)
import secrets
from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from src.auth.models import Account
from src.auth.repository import AccountRepository, SessionRepository
from src.auth.service import AuthService
from src.common.database import get_async_session
from src.core.config import get_settings

SESSION_COOKIE = "cookmark_session"
_BEARER_PREFIX = "bearer "

# 401은 아래 get_current_account가 실제로 내는 응답이다 — 이를 쓰는 모든 도메인의 라우트가
# responses=UNAUTHORIZED로 문서화해야 생성된 OpenAPI가 구현과 어긋나지 않는다(#99 계약 가드).
UNAUTHORIZED: dict[int | str, dict[str, str]] = {
    401: {"description": "세션이 없거나 유효하지 않다"}
}

# 403은 아래 require_register_key가 내는 응답이다 (#167). **401과 코드가 갈리는 것이 요점이다** —
# 401은 "신원을 대라"라 앱의 "401이면 재등록"(#168)을 발화시키는데, 등록 자체가 401을 내면
# 재등록 루프가 된다. 등록 키는 재시도로 못 고치는 거부이므로(회전 = APK 재배포) 403이다.
REGISTRATION_REFUSED: dict[int | str, dict[str, str]] = {
    403: {"description": "등록 키가 없거나 유효하지 않다"}
}


def get_auth_service(
    session: Annotated[AsyncSession, Depends(get_async_session)],
) -> AuthService:
    # 두 Repository가 같은 session을 공유한다 — 트랜잭션 경계는 서비스가 정한다 (§3).
    return AuthService(AccountRepository(session), SessionRepository(session))


def extract_session_token(request: Request) -> str | None:
    """저장은 하나, 운반만 플랫폼별이다 — 네이티브는 Bearer, 웹은 쿠키. 토큰은 같은 값이다 (§9).

    Authorization 헤더가 쿠키를 이긴다 — 명시가 암묵을 이긴다. **빈 Bearer도 명시다**: 헤더가
    있으면 값이 비어도 쿠키로 떨어지지 않는다. 그래서 파싱만 _bearer_value에 위임하고 그 함수의
    반환을 곧바로 폴백 신호로 쓰지는 않는다 — if 안에서 돌려주는 것이 그 차이다.
    """
    header = request.headers.get("authorization")
    if header and header.lower().startswith(_BEARER_PREFIX):
        return _bearer_value(header)
    return request.cookies.get(SESSION_COOKIE)


async def require_register_key(
    authorization: Annotated[str | None, Header()] = None,
) -> None:
    """익명 기기 등록의 문지기 — 빌드에 박힌 등록 키를 요구한다 (#167 · ADR-0012).

    **쿠키를 보지 않는다.** 위 extract_session_token은 헤더가 없으면 쿠키로 폴백하는데, 등록이
    그걸 재사용하면 남아 있던 세션 쿠키가 등록 키로 읽힌다. 같은 헤더를 쓰되 추출은 갈린다.

    **DB를 만지기 전에 거부한다** — 라우트 레벨 의존성으로 꽂혀 세션 조립보다 먼저 돈다. CI의
    계약 fuzzing은 자리표시자 DATABASE_URL로 도는 실 서버라, 여기서 안 막으면 죽은 DB를 때린다.

    **없음과 틀림이 바이트 동일한 403**이다 — 공개 URL에서 어느 쪽인지 알려줄 이유가 없다
    (부재와 남의 것을 같은 404로 내는 recipes의 관용구와 동형).
    """
    presented = _bearer_value(authorization)
    expected = get_settings().register_key.get_secret_value()
    # **bytes로 비교하고, 코덱을 좌우가 다르게 쓴다.** 둘 다 이유가 있다.
    #   ① compare_digest는 비-ASCII str에 TypeError를 던진다. Starlette이 헤더를 latin-1로
    #      디코드하므로 스캐너가 보낸 0x80 이상 바이트가 그대로 도착하고, str끼리 비교하면
    #      403이어야 할 요청이 500이 된다.
    #   ② presented는 latin-1로 **디코드된** 값이라 같은 코덱으로 되감아야 회선의 원본 바이트가
    #      복원된다. UTF-8로 되감으면 비-ASCII 키가 영원히 불일치한다. expected는 env에서 온
    #      진짜 문자열이므로 UTF-8이 맞다. 키를 ASCII로 만들면 둘은 같아지고, infra/README가
    #      실제로 ASCII 생성을 지시한다 — 이 비대칭은 그 지시가 깨졌을 때의 안전망이다.
    if presented is None or not secrets.compare_digest(
        presented.encode("latin-1", "replace"), expected.encode("utf-8")
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="등록 키가 없거나 유효하지 않다",
        )


def _bearer_value(header: str | None) -> str | None:
    if header and header.lower().startswith(_BEARER_PREFIX):
        return header[len(_BEARER_PREFIX) :].strip() or None
    return None


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
