# 로그인 관통 — IdP mock으로 콜백까지 앱을 지나 계정 생성·세션 발급·쿠키 세팅을 검증한다 (AC 1·2·3)
import httpx
import pytest
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import col

from src.auth.dependencies import SESSION_COOKIE
from src.auth.models import Account
from src.auth.oidc import PROVIDERS, Provider
from tests.idp import IMPOSTOR_KEY, FakeIdp


def session_set_cookie(response: httpx.Response) -> str:
    """세션 쿠키의 Set-Cookie 헤더 — SessionMiddleware의 OAuth state 쿠키와 섞여 오므로 골라낸다."""
    return next(
        header
        for header in response.headers.get_list("set-cookie")
        if header.startswith(f"{SESSION_COOKIE}=")
    )


async def count_accounts(db_session: AsyncSession, sub: str) -> int:
    result = await db_session.execute(
        select(func.count()).select_from(Account).where(col(Account.sub) == sub)
    )
    return result.scalar_one()


@pytest.mark.parametrize("provider", [Provider.KAKAO, Provider.GOOGLE])
async def test_callback_creates_account_and_issues_session(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    db_session: AsyncSession,
    provider: Provider,
) -> None:
    """AC: 콜백 → 계정 생성(iss+sub) → 세션 발급 → 쿠키 세팅 (카카오·구글 각각)."""
    sub = f"fresh-user-{provider.value}"

    res = await idp.login(client, provider, sub=sub)

    assert res.status_code == 200, res.text
    body = res.json()
    assert body["account"]["iss"] == PROVIDERS[provider].issuer
    assert body["account"]["sub"] == sub
    assert body["token"]
    assert await count_accounts(db_session, sub) == 1


@pytest.mark.parametrize("provider", [Provider.KAKAO, Provider.GOOGLE])
async def test_callback_sets_httponly_secure_lax_cookie(
    client: httpx.AsyncClient, idp: FakeIdp, provider: Provider
) -> None:
    """AC: 웹 운반은 HttpOnly·Secure·SameSite=Lax 쿠키 (backend.md §9)."""
    res = await idp.login(client, provider, sub=f"cookie-attrs-{provider.value}")

    cookie = session_set_cookie(res)
    assert "HttpOnly" in cookie
    assert "Secure" in cookie
    assert "samesite=lax" in cookie.lower()


async def test_relogin_with_same_identity_reuses_account(
    client: httpx.AsyncClient, idp: FakeIdp, db_session: AsyncSession
) -> None:
    """AC: 같은 iss+sub 재로그인 시 계정 중복 생성 없음."""
    sub = "returning-user"

    first = await idp.login(client, Provider.KAKAO, sub=sub)
    second = await idp.login(client, Provider.KAKAO, sub=sub)

    assert first.json()["account"]["id"] == second.json()["account"]["id"]
    assert await count_accounts(db_session, sub) == 1
    # 계정은 하나지만 세션은 로그인마다 새로 난다 — 한 쪽 로그아웃이 다른 쪽을 죽이지 않는다.
    assert first.json()["token"] != second.json()["token"]


async def test_same_sub_from_different_providers_are_different_accounts(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """iss가 계정 키의 일부다 — 카카오와 구글이 우연히 같은 sub를 줘도 남남이다 (ADR-0009 #87: 1기 감수)."""
    kakao = await idp.login(client, Provider.KAKAO, sub="collision")
    google = await idp.login(client, Provider.GOOGLE, sub="collision")

    assert kakao.json()["account"]["id"] != google.json()["account"]["id"]


async def test_accounts_table_has_no_email_or_profile_columns(
    db_session: AsyncSession,
) -> None:
    """AC: 계정 테이블에 이메일·프로필 컬럼이 존재하지 않음 (§12.1 최소 식별자).

    모델 코드가 아니라 실 DB의 스키마를 본다 — 계정은 (내부 id, iss, sub, created_at)이 전부다.
    """
    result = await db_session.execute(
        text(
            "SELECT column_name FROM information_schema.columns WHERE table_name = 'accounts'"
        )
    )

    assert {row[0] for row in result} == {"id", "iss", "sub", "created_at"}


async def test_login_rejects_id_token_signed_by_impostor(
    client: httpx.AsyncClient, idp: FakeIdp, db_session: AsyncSession
) -> None:
    """ID 토큰 검증이 실제로 돈다 — IdP의 JWKS로 검증되지 않는 토큰은 계정을 만들지 못한다."""
    res = await idp.login(client, Provider.KAKAO, sub="impostor-user", key=IMPOSTOR_KEY)

    assert res.status_code == 401
    assert await count_accounts(db_session, "impostor-user") == 0


async def test_callback_without_login_start_is_rejected(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """state 없이 콜백을 직접 때리면 실패한다 — CSRF state 검증은 authlib가 한다."""
    res = await client.get(
        "/api/v1/auth/kakao/callback", params={"code": "x", "state": "forged"}
    )

    assert res.status_code == 401


async def test_login_start_redirects_to_provider(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    res = await client.get("/api/v1/auth/kakao/login")

    assert res.status_code == 302
    assert res.headers["location"].startswith(f"{PROVIDERS[Provider.KAKAO].issuer}/")


async def test_unknown_provider_is_422(client: httpx.AsyncClient) -> None:
    res = await client.get("/api/v1/auth/naver/login")

    assert res.status_code == 422
