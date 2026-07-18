# 레시피 북 CRUD — 실 DB 관통. 저장·조회에 추출 재료 동봉, 추출 실패는 명시적 502 (티켓 #103 AC)
from uuid import uuid4

import httpx
import pytest
from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import col

from src.auth.oidc import Provider
from src.llm.exceptions import UpstreamLLMError
from src.recipes.models import Recipe
from tests.idp import FakeIdp
from tests.llm import VIDEO_EXTRACTION, FakeLLMService

RECIPES = "/api/v1/recipes"


@pytest.fixture(autouse=True)
def _llm_guard(migrated_db: str, fake_llm: FakeLLMService) -> FakeLLMService:
    """전 테스트에 페이크 주입을 강제한다 — override 누락 시 실 Gemini로 새는 함정 차단.

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


async def test_create_returns_extracted_ingredients(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    fake_llm: FakeLLMService,
    db_session: AsyncSession,
) -> None:
    """AC: 저장 응답에 추출 재료 동봉 — 추출은 저장 시 서버가 1회 수행한다."""
    headers = await login_bearer(client, idp, "crud-create")

    res = await client.post(
        RECIPES,
        json={"url": "https://youtu.be/crud-create", "title": "김치찌개"},
        headers=headers,
    )

    assert res.status_code == 201
    body = res.json()
    assert body["url"] == "https://youtu.be/crud-create"
    assert body["title"] == "김치찌개"
    assert body["ingredients"] == VIDEO_EXTRACTION
    assert "id" in body and "created_at" in body
    # url이 extract로 전달된다(#123) — 유튜브 URL은 영상 직독 단으로 가고 제목 추론은 안 탄다.
    assert fake_llm.video_urls == ["https://youtu.be/crud-create"]
    assert fake_llm.extracted_titles == []
    stored = await count_rows(db_session, count_by_url("https://youtu.be/crud-create"))
    assert stored == 1


async def test_get_by_id_returns_ingredients(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """AC: 조회에도 추출 재료 동봉 — 추출 결과는 항목에 남는 것이지 응답 1회용이 아니다."""
    headers = await login_bearer(client, idp, "crud-get")
    created = (
        await client.post(
            RECIPES,
            json={"url": "https://youtu.be/crud-get", "title": "계란찜"},
            headers=headers,
        )
    ).json()

    res = await client.get(f"{RECIPES}/{created['id']}", headers=headers)

    assert res.status_code == 200
    assert res.json()["ingredients"] == VIDEO_EXTRACTION


async def test_list_keeps_insertion_order(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """목록은 삽입순 — 모바일 레시피 북 표시 순서(append)와 패리티."""
    headers = await login_bearer(client, idp, "crud-list-order")
    for n in (1, 2):
        await client.post(
            RECIPES,
            json={"url": f"https://youtu.be/order-{n}", "title": f"요리 {n}"},
            headers=headers,
        )

    res = await client.get(RECIPES, headers=headers)

    assert res.status_code == 200
    assert [r["url"] for r in res.json()] == [
        "https://youtu.be/order-1",
        "https://youtu.be/order-2",
    ]


async def test_patch_updates_title_without_reextraction(
    client: httpx.AsyncClient, idp: FakeIdp, fake_llm: FakeLLMService
) -> None:
    """수정은 재추출하지 않는다 — 추출은 저장 시 1회뿐이다(글로서리)."""
    headers = await login_bearer(client, idp, "crud-patch-title")
    created = (
        await client.post(
            RECIPES,
            json={"url": "https://youtu.be/patch-title", "title": "김치찌개"},
            headers=headers,
        )
    ).json()

    res = await client.patch(
        f"{RECIPES}/{created['id']}", json={"title": "부대찌개"}, headers=headers
    )

    assert res.status_code == 200
    body = res.json()
    assert body["title"] == "부대찌개"
    assert body["url"] == "https://youtu.be/patch-title"  # url 불변
    assert body["ingredients"] == VIDEO_EXTRACTION  # 재료 불변
    assert fake_llm.video_urls == [
        "https://youtu.be/patch-title"
    ]  # 생성 1회뿐 — 재추출 없음


async def test_patch_replaces_ingredients(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """재료는 사용자가 직접 고친다 — 통째 교체."""
    headers = await login_bearer(client, idp, "crud-patch-ingredients")
    created = (
        await client.post(
            RECIPES,
            json={"url": "https://youtu.be/patch-ing", "title": "된장찌개"},
            headers=headers,
        )
    ).json()

    res = await client.patch(
        f"{RECIPES}/{created['id']}",
        json={"ingredients": ["두부", "애호박"]},
        headers=headers,
    )

    assert res.status_code == 200
    assert res.json()["ingredients"] == ["두부", "애호박"]


async def test_patch_rejects_url_change(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """url은 불변 — 조용한 무시가 아니라 422로 시끄럽게 거절한다(#34 계열 금지)."""
    headers = await login_bearer(client, idp, "crud-patch-url")
    created = (
        await client.post(
            RECIPES,
            json={"url": "https://youtu.be/immutable", "title": "잡채"},
            headers=headers,
        )
    ).json()

    res = await client.patch(
        f"{RECIPES}/{created['id']}",
        json={"url": "https://youtu.be/other"},
        headers=headers,
    )

    assert res.status_code == 422


async def test_create_rejects_client_ingredients(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """재료는 서버 추출 결과만 — 클라이언트가 심는 경로는 422로 막는다."""
    headers = await login_bearer(client, idp, "crud-create-forbid")

    res = await client.post(
        RECIPES,
        json={
            "url": "https://youtu.be/forbid",
            "title": "비빔밥",
            "ingredients": ["몰래 심은 재료"],
        },
        headers=headers,
    )

    assert res.status_code == 422


async def test_create_with_missing_title_is_422(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    res = await client.post(
        RECIPES,
        json={"url": "https://youtu.be/no-title"},
        headers=await login_bearer(client, idp, "crud-create-422"),
    )

    assert res.status_code == 422


async def test_delete_removes_row(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    db_session: AsyncSession,
) -> None:
    headers = await login_bearer(client, idp, "crud-delete")
    created = (
        await client.post(
            RECIPES,
            json={"url": "https://youtu.be/delete-me", "title": "떡볶이"},
            headers=headers,
        )
    ).json()

    res = await client.delete(f"{RECIPES}/{created['id']}", headers=headers)

    assert res.status_code == 204
    after = await client.get(f"{RECIPES}/{created['id']}", headers=headers)
    assert after.status_code == 404
    stored = await count_rows(db_session, count_by_url("https://youtu.be/delete-me"))
    assert stored == 0


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("POST", RECIPES),
        ("GET", RECIPES),
        ("GET", f"{RECIPES}/{uuid4()}"),
        ("PATCH", f"{RECIPES}/{uuid4()}"),
        ("DELETE", f"{RECIPES}/{uuid4()}"),
    ],
)
async def test_all_recipe_routes_require_session(
    client: httpx.AsyncClient, method: str, path: str
) -> None:
    """AC 전제: 무세션은 전 라우트 401 — CurrentAccount가 본문 검증(422)보다 먼저 선다."""
    res = await client.request(method, path)

    assert res.status_code == 401


async def test_malformed_body_is_400_even_before_auth(
    client: httpx.AsyncClient,
) -> None:
    """FastAPI는 본문 JSON 디코드를 의존성 해석보다 먼저 한다 — 깨진 본문은 401이 아니라 400이다.

    이 순서는 우리가 정한 게 아니라 프레임워크의 것이다 — 계약(문서화된 400)이 실서버와 어긋나지
    않는지 핀한다(schemathesis가 실측으로 잡았던 미문서화 코드).
    """
    res = await client.post(
        RECIPES, content=b"\x80", headers={"Content-Type": "application/json"}
    )

    assert res.status_code == 400


@pytest.mark.parametrize("method", ["GET", "PATCH", "DELETE"])
async def test_nonexistent_id_is_404_for_owner(
    client: httpx.AsyncClient, idp: FakeIdp, method: str
) -> None:
    """자기 세션이라도 없는 id는 404 — 교차 테넌트 404와 바이트 동일 응답이어야 한다."""
    headers = await login_bearer(client, idp, f"crud-404-{method.lower()}")
    kwargs: dict[str, object] = {"json": {}} if method == "PATCH" else {}

    res = await client.request(
        method,
        f"{RECIPES}/{uuid4()}",
        headers=headers,
        **kwargs,  # type: ignore[arg-type]
    )

    assert res.status_code == 404


async def test_extraction_failure_is_502_and_no_row(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    fake_llm: FakeLLMService,
    db_session: AsyncSession,
) -> None:
    """AC: 추출 실패는 명시적 502 — 재료 0개로 조용히 저장하지 않는다(#34 선례 서버 반복 금지)."""
    headers = await login_bearer(client, idp, "crud-extract-fail")
    fake_llm.failure = UpstreamLLMError("추출 업스트림 불능")

    res = await client.post(
        RECIPES,
        json={"url": "https://youtu.be/fail", "title": "알 수 없는 요리"},
        headers=headers,
    )

    assert res.status_code == 502
    stored = await count_rows(db_session, count_by_url("https://youtu.be/fail"))
    assert stored == 0


async def test_extraction_empty_list_still_saves(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """빈 배열은 실패가 아니다 — 요리명 미인식 시 []는 프롬프트가 정의한 정상 출력이다.

    url은 .invalid TLD(RFC 6761 영구 미해석) — fetch 단이 결정적으로 실패해 제목 추론 폴백을 탄다(#123).
    """
    headers = await login_bearer(client, idp, "crud-extract-empty")

    res = await client.post(
        RECIPES,
        json={"url": "https://recipe.invalid/empty", "title": "ㅁㄴㅇㄹ"},
        headers=headers,
    )

    assert res.status_code == 201
    assert res.json()["ingredients"] == []
