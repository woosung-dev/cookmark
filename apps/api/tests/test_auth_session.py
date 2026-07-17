# 세션 검증 표면 — 쿠키·Bearer 운반, 무세션·위조·만료 401, 로그아웃·탈퇴 즉시 무효화 (AC 4·5·6)
from datetime import UTC, datetime, timedelta
from uuid import UUID

import httpx
from sqlalchemy import Select, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import col

from src.auth.models import Account, AuthSession
from src.auth.oidc import Provider
from src.auth.service import hash_token
from tests.idp import FakeIdp

ME = "/api/v1/auth/me"


async def count_rows(db_session: AsyncSession, statement: Select[tuple[int]]) -> int:
    result = await db_session.execute(statement)
    return result.scalar_one()


async def test_me_with_cookie(client: httpx.AsyncClient, idp: FakeIdp) -> None:
    """AC: 쿠키로 현재 계정 조회 성공 — 브라우저는 토큰을 신경쓰지 않는다."""
    await idp.login(client, Provider.KAKAO, sub="cookie-user")

    res = await client.get(ME)  # 쿠키 jar가 자동 운반

    assert res.status_code == 200
    assert res.json()["sub"] == "cookie-user"


async def test_me_with_bearer(client: httpx.AsyncClient, idp: FakeIdp) -> None:
    """AC: Bearer로 현재 계정 조회 성공 — 네이티브는 같은 토큰을 헤더로 운반한다 (§9)."""
    token = (await idp.login(client, Provider.KAKAO, sub="bearer-user")).json()["token"]
    client.cookies.clear()  # 쿠키를 지워 Bearer만으로 통과하는지 본다

    res = await client.get(ME, headers={"Authorization": f"Bearer {token}"})

    assert res.status_code == 200
    assert res.json()["sub"] == "bearer-user"


async def test_me_without_session_is_401(client: httpx.AsyncClient) -> None:
    """AC: 무세션은 401."""
    res = await client.get(ME)

    assert res.status_code == 401


async def test_me_with_forged_token_is_401(client: httpx.AsyncClient) -> None:
    """AC: 위조 토큰은 401 — 불투명 ID라 추측으로 만들 수 없다."""
    res = await client.get(ME, headers={"Authorization": "Bearer forged-token-xyz"})

    assert res.status_code == 401


async def test_logout_kills_the_token_immediately(
    client: httpx.AsyncClient, idp: FakeIdp, db_session: AsyncSession
) -> None:
    """AC: 로그아웃 직후 같은 토큰 401 — 만료 대기 없는 즉시 무효화(세션 채택의 근거, #77)."""
    token = (await idp.login(client, Provider.KAKAO, sub="leaving-device")).json()[
        "token"
    ]

    logout = await client.post("/api/v1/auth/logout")

    assert logout.status_code == 204
    after = await client.get(ME, headers={"Authorization": f"Bearer {token}"})
    assert after.status_code == 401
    # 로그아웃 = 세션 행 삭제 (§9) — 만료 표시로 눕혀두는 게 아니다.
    remaining = await count_rows(
        db_session,
        select(func.count())
        .select_from(AuthSession)
        .where(col(AuthSession.token_hash) == hash_token(token)),
    )
    assert remaining == 0


async def test_logout_leaves_other_sessions_alive(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """한 기기 로그아웃이 다른 기기를 죽이지 않는다 — 세션은 기기별로 난다."""
    first = (await idp.login(client, Provider.KAKAO, sub="two-device")).json()["token"]
    second = (await idp.login(client, Provider.KAKAO, sub="two-device")).json()["token"]

    await client.post(
        "/api/v1/auth/logout", headers={"Authorization": f"Bearer {first}"}
    )

    still = await client.get(ME, headers={"Authorization": f"Bearer {second}"})
    assert still.status_code == 200


async def test_withdraw_hard_deletes_account_and_sessions(
    client: httpx.AsyncClient, idp: FakeIdp, db_session: AsyncSession
) -> None:
    """AC: 탈퇴 직후 계정·세션 행 0, 같은 토큰 401 (§12.3 즉시 하드 삭제 · soft delete 금지)."""
    login = (await idp.login(client, Provider.KAKAO, sub="withdrawing-user")).json()
    token = login["token"]
    account_id = UUID(login["account"]["id"])

    res = await client.delete("/api/v1/auth/account")

    assert res.status_code == 204
    accounts = await count_rows(
        db_session,
        select(func.count()).select_from(Account).where(col(Account.id) == account_id),
    )
    sessions = await count_rows(
        db_session,
        select(func.count())
        .select_from(AuthSession)
        .where(col(AuthSession.account_id) == account_id),
    )
    assert (accounts, sessions) == (0, 0)  # 세션은 FK CASCADE로 함께 죽는다
    after = await client.get(ME, headers={"Authorization": f"Bearer {token}"})
    assert after.status_code == 401


async def test_withdraw_without_session_is_401(client: httpx.AsyncClient) -> None:
    """탈퇴는 세션에서 계정을 꺼낸다 — 클라이언트가 계정 id를 대는 경로가 없다 (§9)."""
    res = await client.delete("/api/v1/auth/account")

    assert res.status_code == 401


async def test_expired_session_is_401(
    client: httpx.AsyncClient, idp: FakeIdp, db_session: AsyncSession
) -> None:
    """만료된 세션은 통과하지 않는다 — 쿠키 Max-Age의 서버측 짝."""
    login = (await idp.login(client, Provider.KAKAO, sub="expiring-user")).json()
    account_id = UUID(login["account"]["id"])
    await db_session.execute(
        update(AuthSession)
        .where(col(AuthSession.account_id) == account_id)
        .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
    )
    await db_session.commit()

    res = await client.get(ME, headers={"Authorization": f"Bearer {login['token']}"})

    assert res.status_code == 401


async def test_session_token_is_not_stored_in_plaintext(
    client: httpx.AsyncClient, idp: FakeIdp, db_session: AsyncSession
) -> None:
    """DB 최종 상태 — 원문 토큰으로는 세션이 조회되지 않는다.

    DB·백업 유출이 곧 세션 탈취가 되지 않게 해시만 남긴다. ADR-0009가 PITR 백업 잔존을
    명시적으로 인정하므로(§12.3), 그 잔존물이 살아있는 세션이면 안 된다.
    """
    token = (await idp.login(client, Provider.KAKAO, sub="hash-check-user")).json()[
        "token"
    ]

    stored = await count_rows(
        db_session,
        select(func.count())
        .select_from(AuthSession)
        .where(col(AuthSession.token_hash) == token),
    )

    assert stored == 0
