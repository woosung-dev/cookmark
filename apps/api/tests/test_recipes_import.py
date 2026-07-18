# 데이터 이전 bulk 가져오기 — 실 DB 관통. 재추출 없는 원자적 등록·재료 보존·격리 (티켓 #104 AC)
import httpx
import pytest
from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import col

from src.auth.oidc import Provider
from src.recipes.models import Recipe
from tests.idp import FakeIdp
from tests.llm import FakeLLMService

IMPORT = "/api/v1/migration/recipes"
RECIPES = "/api/v1/recipes"


@pytest.fixture(autouse=True)
def _llm_guard(migrated_db: str, fake_llm: FakeLLMService) -> FakeLLMService:
    """전 테스트에 페이크 주입을 강제한다 — 이전은 LLM을 부르지 않아야 하므로, 실 Gemini 유출은 곧 버그다.

    migrated_db 의존이 먼저다 — fake_llm이 src.main을 import하므로 env 주입이 선행돼야 한다.
    """
    return fake_llm


async def login_bearer(
    client: httpx.AsyncClient, idp: FakeIdp, sub: str
) -> dict[str, str]:
    """실 로그인 관통 후 Bearer 헤더 반환 — 쿠키 jar 잔존이 계정을 섞지 않게 비운다."""
    token = (await idp.login(client, Provider.KAKAO, sub=sub)).json()["token"]
    client.cookies.clear()
    return {"Authorization": f"Bearer {token}"}


async def count_rows(db_session: AsyncSession, statement: Select[tuple[int]]) -> int:
    result = await db_session.execute(statement)
    return result.scalar_one()


def count_by_url(url: str) -> Select[tuple[int]]:
    return select(func.count()).select_from(Recipe).where(col(Recipe.url) == url)


async def test_bulk_import_saves_all_scoped_preserving_ingredients(
    client: httpx.AsyncClient,
    idp: FakeIdp,
) -> None:
    """AC: N개를 요청 계정 스코프로 전부 저장하고, 재료를 보낸 그대로 보존한다(빈 배열·특수 문자열 포함)."""
    headers = await login_bearer(client, idp, "import-happy")
    items = [
        {
            "url": "https://youtu.be/imp-1",
            "title": "김치찌개",
            "ingredients": ["김치", "돼지고기", "두부"],
        },
        # 빈 배열도 그대로 보존한다 — 로컬에서 추출이 []였던 항목이다(실패 아님).
        {"url": "https://youtu.be/imp-2", "title": "미분류 요리", "ingredients": []},
        # 서버가 손대지 않는다는 증거 — 공백·괄호 그대로.
        {
            "url": "https://youtu.be/imp-3",
            "title": "된장찌개",
            "ingredients": ["두부 (반 모)", "애호박", "대파"],
        },
    ]

    res = await client.post(IMPORT, json={"recipes": items}, headers=headers)

    assert res.status_code == 201
    body = res.json()
    assert [r["url"] for r in body] == [i["url"] for i in items]
    assert [r["ingredients"] for r in body] == [i["ingredients"] for i in items]
    assert all("id" in r and "created_at" in r for r in body)
    # 목록도 삽입순으로 전부 돌려준다 — 저장이 실제로 남았다는 확인.
    listed = (await client.get(RECIPES, headers=headers)).json()
    assert [r["url"] for r in listed] == [i["url"] for i in items]
    assert [r["ingredients"] for r in listed] == [i["ingredients"] for i in items]


async def test_import_calls_llm_zero_times(
    client: httpx.AsyncClient, idp: FakeIdp, fake_llm: FakeLLMService
) -> None:
    """AC: 등록 중 LLM seam 호출 0회 — 재료는 이미 추출됐고 그대로 수용한다(재추출 없음).

    구조적으로도 성립한다 — RecipeImportService는 BaseLLMService를 아예 주입받지 않는다.
    """
    headers = await login_bearer(client, idp, "import-no-llm")

    res = await client.post(
        IMPORT,
        json={
            "recipes": [
                {
                    "url": "https://youtu.be/no-llm",
                    "title": "김치찌개",
                    "ingredients": ["김치"],
                }
            ]
        },
        headers=headers,
    )

    assert res.status_code == 201
    assert fake_llm.extracted_titles == []
    assert fake_llm.recognized_images == []
    assert fake_llm.match_calls == []


async def test_import_is_atomic_all_or_nothing_on_mid_item_failure(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    db_session: AsyncSession,
) -> None:
    """AC: 중간 항목이 실패하면 전체 롤백 — 저장 행 0(부분 저장 없음).

    NUL(\\x00)은 Postgres text가 거부한다 — 중간 항목 title에 심어 mid-batch flush 실패를 결정적으로
    만든다. 앞 항목은 이미 flush돼 트랜잭션에 떠 있지만, commit에 도달하지 못해 전부 롤백된다.
    """
    headers = await login_bearer(client, idp, "import-atomic")
    items = [
        {"url": "https://youtu.be/atom-0", "title": "정상 앞", "ingredients": ["김치"]},
        {"url": "https://youtu.be/atom-1", "title": "깨진\x00제목", "ingredients": []},
        {"url": "https://youtu.be/atom-2", "title": "정상 뒤", "ingredients": ["두부"]},
    ]

    res = await client.post(IMPORT, json={"recipes": items}, headers=headers)

    assert res.status_code == 500
    # 서비스가 잡아 변환한 문서화된 실패다 — 미처리 500(제너릭 detail)이 아니라는 핀.
    assert res.json()["detail"] == "가져오기에 실패해 아무것도 저장하지 않았다"
    # 배치 전체가 사라진다 — 실패 앞 항목도 남지 않는다.
    for item in items:
        assert await count_rows(db_session, count_by_url(item["url"])) == 0


async def test_import_success_and_failure_are_distinguishable(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """AC: 응답이 성공/실패를 명확히 구분 — 클라이언트가 로컬 삭제 여부를 이 코드로 판단한다."""
    headers = await login_bearer(client, idp, "import-signal")

    ok = await client.post(
        IMPORT,
        json={
            "recipes": [
                {
                    "url": "https://youtu.be/sig-ok",
                    "title": "계란찜",
                    "ingredients": ["계란"],
                }
            ]
        },
        headers=headers,
    )
    fail = await client.post(
        IMPORT,
        json={
            "recipes": [
                {
                    "url": "https://youtu.be/sig-fail",
                    "title": "x\x00y",
                    "ingredients": [],
                }
            ]
        },
        headers=headers,
    )

    assert ok.status_code == 201
    assert fail.status_code == 500


async def test_import_isolated_between_accounts(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """AC: 다른 계정으로 오염될 방법이 구조적으로 없다 — A가 넣은 항목은 B 목록에 안 보인다."""
    alice = await login_bearer(client, idp, "import-alice")
    bob = await login_bearer(client, idp, "import-bob")

    await client.post(
        IMPORT,
        json={
            "recipes": [
                {
                    "url": "https://youtu.be/a-only",
                    "title": "잡채",
                    "ingredients": ["당면"],
                }
            ]
        },
        headers=alice,
    )

    alice_list = (await client.get(RECIPES, headers=alice)).json()
    bob_list = (await client.get(RECIPES, headers=bob)).json()
    assert [r["url"] for r in alice_list] == ["https://youtu.be/a-only"]
    assert bob_list == []


async def test_import_requires_session(client: httpx.AsyncClient) -> None:
    """AC: 무세션 401 — CurrentAccount가 본문 검증(422)보다 먼저 선다."""
    res = await client.post(
        IMPORT,
        json={"recipes": [{"url": "https://x", "title": "y", "ingredients": []}]},
    )

    assert res.status_code == 401


async def test_import_malformed_body_is_400(client: httpx.AsyncClient) -> None:
    """본문 받는 라우트의 숨은 400 — FastAPI는 JSON 디코드를 의존성 해석보다 먼저 한다(#103 실측)."""
    res = await client.post(
        IMPORT, content=b"\x80", headers={"Content-Type": "application/json"}
    )

    assert res.status_code == 400


async def test_import_empty_batch_is_422(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """빈 배치는 422 — 로컬에 레시피가 있을 때만 부르는 요청이라 빈 배열은 계약 위반이다."""
    headers = await login_bearer(client, idp, "import-empty")

    res = await client.post(IMPORT, json={"recipes": []}, headers=headers)

    assert res.status_code == 422


async def test_import_rejects_malformed_item(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """항목 스키마 위반(재료 누락·미지 필드)은 422 — 전량 실패이므로 아무것도 저장되지 않는다."""
    headers = await login_bearer(client, idp, "import-bad-item")

    missing_ingredients = await client.post(
        IMPORT,
        json={"recipes": [{"url": "https://x", "title": "y"}]},
        headers=headers,
    )
    extra_field = await client.post(
        IMPORT,
        json={
            "recipes": [
                {"url": "https://x", "title": "y", "ingredients": [], "sneaky": 1}
            ]
        },
        headers=headers,
    )

    assert missing_ingredients.status_code == 422
    assert extra_field.status_code == 422
