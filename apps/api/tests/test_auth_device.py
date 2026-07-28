# 익명 기기 등록 — 등록 키를 든 요청이 계정+세션을 받고, 1빌드=N계정이 성립한다 (#167 · ADR-0012)
from uuid import UUID, uuid4

import httpx
import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.auth.models import Account
from src.core.config import get_settings
from tests.conftest import REGISTER_KEY
from tests.llm import FakeLLMService

DEVICE = "/api/v1/auth/device"
ME = "/api/v1/auth/me"
RECIPES = "/api/v1/recipes"

# 테스트 파일은 자급자족한다 — 테스트 모듈 간 import 금지(test_recipes_isolation.py 관례).
# conftest의 REGISTER_KEY만 예외다: 앱에 주입된 그 값이어야 진짜 비교를 관통한다.
KEY_HEADER = {"Authorization": f"Bearer {REGISTER_KEY}"}


@pytest.fixture(autouse=True)
def _llm_guard(migrated_db: str, fake_llm: FakeLLMService) -> FakeLLMService:
    """레시피 저장이 재료 추출로 LLM을 부른다 — 실 Gemini에 나가지 않게 페이크를 꽂는다.

    migrated_db를 먼저 받는 순서가 중요하다(fake_llm이 src.main을 import한다) — isolation 선례.
    """
    return fake_llm


async def register(client: httpx.AsyncClient) -> dict[str, object]:
    """등록 1회 — 쿠키 jar를 비워 계정이 조용히 섞이지 않게 한다(login_bearer 관례)."""
    res = await client.post(DEVICE, headers=KEY_HEADER)
    assert res.status_code == 200, res.text
    client.cookies.clear()
    body: dict[str, object] = res.json()
    return body


def bearer(session: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {session['token']}"}


async def count_accounts(db_session: AsyncSession) -> int:
    result = await db_session.execute(select(func.count()).select_from(Account))
    return result.scalar_one()


async def test_registration_issues_an_anonymous_account_and_session(
    client: httpx.AsyncClient,
) -> None:
    """AC: 익명 계정 (iss="device", sub=<서버 발급 uuid>)와 세션을 함께 발급한다.

    응답은 로그인 콜백과 **같은 세션 스키마**를 재사용한다 — 새 계약 표면을 만들지 않는다.
    """
    issued = await register(client)

    account = issued["account"]
    assert isinstance(account, dict)
    assert account["iss"] == "device"
    # sub은 서버가 만든다 — 클라이언트가 대는 경로가 없다(§9의 "userId를 인자로 받지 않는다").
    assert UUID(str(account["sub"]))
    assert issued["token"] and issued["expires_at"]


async def test_issued_token_opens_protected_routes(client: httpx.AsyncClient) -> None:
    """AC: 발급된 토큰으로 **LLM·레시피 북** 라우트가 200이다 — Bearer 운반, 로그인 왕복 0.

    LLM을 빼놓지 않는 이유 — 세션 필수로 닫혀 있던 비용 표면이 바로 그 셋이고, 등록 키는 그것을
    다시 닫으려고 있다. 익명 계정이 그 문을 실제로 여는 것이 이 티켓의 요점이다.
    """
    issued = await register(client)
    headers = bearer(issued)

    me = await client.get(ME, headers=headers)
    recipes = await client.get(RECIPES, headers=headers)
    extract = await client.post(
        "/api/v1/llm/extract", json={"title": "김치찌개"}, headers=headers
    )

    assert me.status_code == 200
    assert me.json()["iss"] == "device"
    assert recipes.status_code == 200
    assert extract.status_code == 200


async def test_every_call_mints_a_different_account(client: httpx.AsyncClient) -> None:
    """AC: 호출할 때마다 다른 계정이 난다 — 1빌드=N계정이 사전프로비저닝과의 결정적 차이다."""
    first = await register(client)
    second = await register(client)

    accounts = (first["account"], second["account"])
    assert all(isinstance(account, dict) for account in accounts)
    assert first["account"]["id"] != second["account"]["id"]  # type: ignore[index]
    assert first["account"]["sub"] != second["account"]["sub"]  # type: ignore[index]
    assert first["token"] != second["token"]


@pytest.mark.parametrize(
    ("name", "headers"),
    [
        ("없음", {}),
        ("틀림", {"Authorization": "Bearer wrong-register-key"}),
        ("빈 값", {"Authorization": "Bearer "}),
        ("스킴 없음", {"Authorization": REGISTER_KEY}),
    ],
)
async def test_bad_register_key_is_refused_without_creating_an_account(
    client: httpx.AsyncClient,
    db_session: AsyncSession,
    name: str,
    headers: dict[str, str],
) -> None:
    """AC: 등록 키가 없거나 틀리면 거부이고 **계정 행이 생기지 않는다**.

    403인 이유 — 재시도로 고칠 수 없는 거부다(회전 = APK 재배포). 401로 내면 앱의 "401이면
    재등록"(#168)과 의미가 겹쳐 재등록 루프가 된다.
    """
    before = await count_accounts(db_session)

    res = await client.post(DEVICE, headers=headers)

    assert res.status_code == 403, name
    assert await count_accounts(db_session) == before, name


async def test_non_ascii_register_key_is_refused_not_crashed(
    client: httpx.AsyncClient, db_session: AsyncSession
) -> None:
    """비-ASCII 바이트를 든 헤더는 500이 아니라 403이다.

    Starlette은 헤더를 latin-1로 디코드하므로 0x80 이상 바이트가 **비-ASCII str**로 도착하는데,
    secrets.compare_digest는 그런 str에 TypeError를 던진다 — str끼리 비교하면 403이어야 할
    요청이 500이 된다. 위협 모델의 "URL을 찍어보는 스캐너"가 정확히 이런 걸 보낸다.
    바이트로 실어 보낸다 — httpx가 헤더 값을 기본 ascii로 인코딩해 문자열로는 재현되지 않는다.
    """
    before = await count_accounts(db_session)

    res = await client.post(
        DEVICE, headers=[(b"authorization", b"Bearer \xff\xfe\x80")]
    )

    assert res.status_code == 403
    assert await count_accounts(db_session) == before


async def test_register_key_does_not_fall_back_to_the_session_cookie(
    client: httpx.AsyncClient, db_session: AsyncSession
) -> None:
    """세션 쿠키를 든 클라이언트가 헤더 없이 등록하면 403이다.

    등록 키와 세션 토큰이 같은 헤더를 쓰지만 **추출기가 다르다** — 기존 extract_session_token은
    헤더가 없으면 쿠키로 폴백하는데, 등록이 그걸 재사용하면 남은 세션 쿠키가 등록 키로 읽힌다.
    """
    issued = await register(client)
    client.cookies.set("cookmark_session", str(issued["token"]), domain="testserver")
    before = await count_accounts(db_session)

    res = await client.post(DEVICE)

    assert res.status_code == 403
    assert await count_accounts(db_session) == before
    client.cookies.clear()


async def test_one_device_cannot_read_another_devices_recipe(
    client: httpx.AsyncClient,
) -> None:
    """AC: 기기 A의 세션으로 기기 B의 레시피에 접근하면 404 — 존재 자체를 노출하지 않는다.

    §12.2 스코프드 레포지토리의 교차 테넌트 관용구를 익명 계정으로 확장한 것이다.
    """
    owner = bearer(await register(client))
    intruder = bearer(await register(client))
    created = await client.post(
        RECIPES,
        json={"title": "기기 A의 레시피", "url": "https://example.com/a"},
        headers=owner,
    )
    assert created.status_code == 201, created.text
    target = f"{RECIPES}/{created.json()['id']}"

    stolen = await client.get(target, headers=intruder)

    assert stolen.status_code == 404
    # 없는 id와 응답이 같아야 "있는데 남의 것"이 새어나가지 않는다.
    missing = await client.get(f"{RECIPES}/{uuid4()}", headers=intruder)
    assert stolen.json() == missing.json()


async def test_key_rotation_only_affects_registration(
    client: httpx.AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """AC: 키 회전은 등록에만 영향한다 — 기존 세션은 불변이고 새 키로 APK를 다시 뿌리면 끝이다.

    이 성질이 없으면 유출 대응이 사용자 데이터를 함께 태운다. 캐시 클리어 관용구는
    test_idp_optional.py 선례 — settings를 읽는 lru_cache를 비워 새 값으로 다시 짓는다.
    """
    issued = await register(client)
    monkeypatch.setenv("COOKMARK_REGISTER_KEY", "rotated-register-key")
    get_settings.cache_clear()
    try:
        stale = await client.post(DEVICE, headers=KEY_HEADER)
        alive = await client.get(ME, headers=bearer(issued))
        rotated = await client.post(
            DEVICE, headers={"Authorization": "Bearer rotated-register-key"}
        )
    finally:
        get_settings.cache_clear()  # monkeypatch가 env를 되돌린 뒤 다시 짓게 한다

    assert stale.status_code == 403  # 옛 키로는 더 못 만든다
    assert alive.status_code == 200  # 이미 발급된 세션은 살아 있다
    assert rotated.status_code == 200  # 새 키로는 즉시 성립한다
    client.cookies.clear()


async def test_registration_does_not_set_a_session_cookie(
    client: httpx.AsyncClient,
) -> None:
    """기기 등록의 선언된 소비자는 네이티브 Bearer 하나뿐이다 (ADR-0012).

    쿠키를 붙이면 공유 쿠키 jar를 쓰는 소비자에서 계정이 조용히 섞인다 — 요청되지 않은 운반을
    만들지 않는다.
    """
    res = await client.post(DEVICE, headers=KEY_HEADER)

    assert res.status_code == 200
    assert not [
        header
        for header in res.headers.get_list("set-cookie")
        if header.startswith("cookmark_session=")
    ]
