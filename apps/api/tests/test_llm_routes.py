# llm 라우트 3종 관통 — ASGI 클라이언트 + 페이크 seam. 화면에 보이는 것(외부 행동)만 검증한다
import base64

import httpx
import pytest

from src.auth.oidc import Provider
from src.llm.exceptions import UpstreamLLMError
from tests.idp import FakeIdp
from tests.llm import FakeLLMService

RECOGNIZE = "/api/v1/llm/recognize"
EXTRACT = "/api/v1/llm/extract"
MATCH = "/api/v1/llm/match"

JPEG_BYTES = b"\xff\xd8\xff\xe0fake-jpeg-768px"
IMAGE_B64 = base64.b64encode(JPEG_BYTES).decode()

# 라우트별 유효 요청 본문 — 401·502 검증에서 본문 탓 422가 끼어들지 않게 한다.
VALID_BODIES = {
    RECOGNIZE: {"image_base64": IMAGE_B64},
    EXTRACT: {"title": "김치찌개"},
    MATCH: {"ingredients": ["대파", "계란", "두부"], "recipes": []},
}


@pytest.fixture
async def authed(client: httpx.AsyncClient, idp: FakeIdp) -> httpx.AsyncClient:
    """세션 쿠키를 실은 클라이언트 — FakeIdp 관통 로그인(#100 하네스 재사용)."""
    await idp.login(client, Provider.KAKAO, sub="llm-user")
    return client


# ── 무세션 401 — 공개 URL의 LLM 비용 표면 보호(티켓 AC) ─────────────────────────


@pytest.mark.parametrize("path", [RECOGNIZE, EXTRACT, MATCH])
async def test_무세션이면_401(client: httpx.AsyncClient, path: str) -> None:
    response = await client.post(path, json=VALID_BODIES[path])
    assert response.status_code == 401


@pytest.mark.parametrize("path", [RECOGNIZE, EXTRACT, MATCH])
async def test_위조_토큰이면_401(client: httpx.AsyncClient, path: str) -> None:
    response = await client.post(
        path,
        json=VALID_BODIES[path],
        headers={"Authorization": "Bearer forged-token-xyz"},
    )
    assert response.status_code == 401


# ── 인식 ────────────────────────────────────────────────────────────────────


async def test_인식_관통_confidence_3단과_usage를_그대로_낸다(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    response = await authed.post(RECOGNIZE, json={"image_base64": IMAGE_B64})
    assert response.status_code == 200
    body = response.json()
    names = [item["name"] for item in body["ingredients"]]
    assert names == ["대파", "계란", "두부", "애호박", "반찬통", "고추장", "표고버섯"]
    assert body["ingredients"][0]["confidence"] == "high"
    assert body["ingredients"][6]["confidence"] == "low"
    assert body["low_quality"] is False
    assert body["usage"]["image_tokens"] == 1064
    assert body["usage"]["cost_usd"] == pytest.approx(0.00073)


async def test_인식_사진은_메모리로만_지나간다(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    """무저장 패스스루(AC) — 디코드된 원본 bytes가 seam에 그대로 닿고, 응답에 이미지가 없다."""
    response = await authed.post(RECOGNIZE, json={"image_base64": IMAGE_B64})
    assert response.status_code == 200
    assert fake_llm.recognized_images == [JPEG_BYTES]
    assert IMAGE_B64 not in response.text


async def test_인식_깨진_base64는_422(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    response = await authed.post(RECOGNIZE, json={"image_base64": "!!!"})
    assert response.status_code == 422
    assert fake_llm.recognized_images == []


# ── 추출 ────────────────────────────────────────────────────────────────────


async def test_추출_관통_제목이_재료_목록이_된다(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    response = await authed.post(EXTRACT, json={"title": "김치찌개"})
    assert response.status_code == 200
    body = response.json()
    assert body["ingredients"] == ["김치", "돼지고기", "두부", "대파", "고춧가루"]
    assert body["usage"]["cost_usd"] == pytest.approx(0.00044)


async def test_추출_제목_공백은_잘라서_전달한다(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    response = await authed.post(EXTRACT, json={"title": "  김치찌개  "})
    assert response.status_code == 200
    assert fake_llm.extracted_titles == ["김치찌개"]


async def test_추출_빈_제목은_422(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    response = await authed.post(EXTRACT, json={"title": "   "})
    assert response.status_code == 422
    assert fake_llm.extracted_titles == []


# ── 매칭 ────────────────────────────────────────────────────────────────────


async def test_매칭_관통_match_score_실산출과_saved_우선(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    response = await authed.post(
        MATCH,
        json={
            "ingredients": ["김치", "두부", "대파", "애호박"],
            "recipes": [
                {
                    "title": "김치찌개",
                    "ingredients": ["김치", "돼지고기", "두부", "대파", "고춧가루"],
                }
            ],
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert [s["menu"] for s in body["suggestions"]] == [
        "김치찌개",
        "애호박볶음",
        "두부조림",
    ]
    assert [s["source"] for s in body["suggestions"]] == [
        "saved",
        "generated",
        "generated",
    ]
    # 산식 결정값 — 부족 0 → 100, 필요 4 중 미해소 1 → 75, substitute 전부 해소 → 100.
    assert [s["match_score"] for s in body["suggestions"]] == [100, 75, 100]
    assert body["suggestions"][2]["missing"] == [{"name": "우유", "substitute": "두유"}]
    assert body["usage"]["cost_usd"] == pytest.approx(0.00044)


async def test_매칭_required는_wire에_없다(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    response = await authed.post(MATCH, json=VALID_BODIES[MATCH])
    assert response.status_code == 200
    assert all("required" not in s for s in response.json()["suggestions"])


async def test_매칭_빈_ingredients는_422(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    response = await authed.post(MATCH, json={"ingredients": [], "recipes": []})
    assert response.status_code == 422
    assert fake_llm.match_calls == []


# ── 업스트림 실패 ────────────────────────────────────────────────────────────


@pytest.mark.parametrize("path", [RECOGNIZE, EXTRACT, MATCH])
async def test_업스트림_실패는_502로_번역된다(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService, path: str
) -> None:
    fake_llm.failure = UpstreamLLMError("업스트림 429")
    response = await authed.post(path, json=VALID_BODIES[path])
    assert response.status_code == 502
    assert response.json()["detail"] == "업스트림 429"
