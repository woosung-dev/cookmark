# 격리·파기 — 교차 테넌트 404, 소유자 스코프 목록, 탈퇴 CASCADE, 스코프드 시그니처 구조 확인 (티켓 #103 AC)
import inspect
from uuid import UUID, uuid4

import httpx
import pytest
from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import col

from src.auth.oidc import Provider
from src.recipes.models import Recipe
from src.recipes.repository import RecipeBookRepository
from tests.idp import FakeIdp
from tests.llm import FakeLLMService

RECIPES = "/api/v1/recipes"


@pytest.fixture(autouse=True)
def _llm_guard(llm: FakeLLMService) -> FakeLLMService:
    """전 테스트에 페이크 주입을 강제한다 — override 누락 시 실 Gemini로 새는 함정 차단."""
    return llm


# 테스트 파일은 자급자족한다(리포 선례 — count_rows도 파일마다 재정의). 테스트 모듈 간 import 금지.
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


async def test_cross_tenant_get_patch_delete_are_404(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """AC: A의 세션으로 B의 레시피 조회·수정·삭제 전부 404 — 403이 아니다(존재를 노출하지 않는다)."""
    owner = await login_bearer(client, idp, "tenant-owner")
    intruder = await login_bearer(client, idp, "tenant-intruder")
    created = (
        await client.post(
            RECIPES,
            json={"url": "https://youtu.be/private", "title": "김치찌개"},
            headers=owner,
        )
    ).json()
    target = f"{RECIPES}/{created['id']}"

    get_res = await client.get(target, headers=intruder)
    patch_res = await client.patch(target, json={"title": "탈취"}, headers=intruder)
    delete_res = await client.delete(target, headers=intruder)

    assert (get_res.status_code, patch_res.status_code, delete_res.status_code) == (
        404,
        404,
        404,
    )
    # 부재와 남의 것이 같은 응답이어야 한다 — 진짜 없는 id의 404와 detail까지 동일한지 본다.
    truly_missing = await client.get(f"{RECIPES}/{uuid4()}", headers=intruder)
    assert get_res.json() == truly_missing.json()
    # 소유자 데이터는 흠집 없이 남는다.
    survived = await client.get(target, headers=owner)
    assert survived.status_code == 200
    assert survived.json()["title"] == "김치찌개"


async def test_list_returns_only_owner_items(
    client: httpx.AsyncClient, idp: FakeIdp
) -> None:
    """AC: 목록이 소유자 항목만 반환 — 남의 항목은 개수로도 새지 않는다."""
    alice = await login_bearer(client, idp, "list-alice")
    bob = await login_bearer(client, idp, "list-bob")
    for n in (1, 2):
        await client.post(
            RECIPES,
            json={"url": f"https://youtu.be/alice-{n}", "title": f"앨리스 {n}"},
            headers=alice,
        )
    await client.post(
        RECIPES,
        json={"url": "https://youtu.be/bob-1", "title": "밥 1"},
        headers=bob,
    )

    alice_list = (await client.get(RECIPES, headers=alice)).json()
    bob_list = (await client.get(RECIPES, headers=bob)).json()

    assert [r["url"] for r in alice_list] == [
        "https://youtu.be/alice-1",
        "https://youtu.be/alice-2",
    ]
    assert [r["url"] for r in bob_list] == ["https://youtu.be/bob-1"]


async def test_withdraw_cascades_recipes_to_zero_rows(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    db_session: AsyncSession,
) -> None:
    """AC: 탈퇴 → 그 계정의 레시피 행 0 — FK ON DELETE CASCADE를 실 DB에서 증명한다(§12.3)."""
    login = (await idp.login(client, Provider.KAKAO, sub="withdrawing-cook")).json()
    headers = {"Authorization": f"Bearer {login['token']}"}
    client.cookies.clear()
    owner_id = UUID(login["account"]["id"])
    for n in (1, 2):
        await client.post(
            RECIPES,
            json={"url": f"https://youtu.be/gone-{n}", "title": f"요리 {n}"},
            headers=headers,
        )

    res = await client.delete("/api/v1/auth/account", headers=headers)

    assert res.status_code == 204
    remaining = await count_rows(
        db_session,
        select(func.count())
        .select_from(Recipe)
        .where(col(Recipe.owner_id) == owner_id),
    )
    assert remaining == 0


def test_repository_is_scoped_at_construction_not_per_method() -> None:
    """AC: owner는 생성자에서 1회 — 메서드로는 남의 행을 달라고 말할 방법 자체가 없다 (§12.2)."""
    init_params = inspect.signature(RecipeBookRepository.__init__).parameters
    assert "owner_id" in init_params

    forbidden = {"owner_id", "owner", "account_id", "user_id"}
    methods = [
        fn
        for name, fn in inspect.getmembers(RecipeBookRepository, inspect.isfunction)
        if not name.startswith("_")
    ]
    assert methods, "공개 메서드가 하나도 없다 — 검사 대상 오류"
    for fn in methods:
        assert not (set(inspect.signature(fn).parameters) & forbidden), (
            f"{fn.__name__}가 owner 인자를 받는다"
        )
