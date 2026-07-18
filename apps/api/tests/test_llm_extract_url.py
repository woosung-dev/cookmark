# URL 추출 사다리 관통 — 유튜브/JSON-LD/본문/제목 폴백 경로와 usage null 계약 (#123)
from collections.abc import Iterator

import httpx
import pytest
import respx

from src.auth.oidc import Provider
from src.common import urlguard
from src.llm import ingest
from src.llm.exceptions import UpstreamLLMError
from tests.idp import FakeIdp
from tests.llm import (
    CONTENT_EXTRACTION,
    EXTRACTIONS,
    VIDEO_EXTRACTION,
    FakeLLMService,
)

EXTRACT = "/api/v1/llm/extract"
RECIPES = "/api/v1/recipes"
BLOG = "https://recipe.example/kimchi-jjigae"

JSONLD_HTML = (
    '<html><head><script type="application/ld+json">'
    '{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},'
    '{"@type":"Recipe","recipeIngredient":["김치 300g","돼지고기 200g","두부 1모"]}]}'
    "</script></head><body>본문</body></html>"
)
PLAIN_HTML = "<html><body><h1>김치찌개 황금 레시피</h1><p>김치와 돼지고기를 볶는다.</p></body></html>"


@pytest.fixture
def pages() -> Iterator[respx.Router]:
    """출처 페이지 mock 전용 respx 컨텍스트 — idp 픽스처와 별개 라우터로 공존한다(fall-through)."""
    with respx.mock(assert_all_called=False) as router:
        yield router


@pytest.fixture
def public_dns(monkeypatch: pytest.MonkeyPatch) -> None:
    """테스트 호스트네임을 공개 IP로 해석 — 공용 가드(urlguard)의 실 DNS를 결정적 페이크로 바꾼다."""

    async def fake_resolve(host: str) -> set[str]:
        return {"93.184.216.34"}

    monkeypatch.setattr(urlguard, "resolve_host", fake_resolve)


@pytest.fixture
async def authed(client: httpx.AsyncClient, idp: FakeIdp) -> httpx.AsyncClient:
    await idp.login(client, Provider.KAKAO, sub="extract-url-user")
    return client


# ── /llm/extract 사다리 ──────────────────────────────────────────────────────


async def test_jsonld_페이지는_LLM_무호출_usage_null(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
    public_dns: None,
) -> None:
    """AC: JSON-LD Recipe가 있으면 결정적 추출 — LLM이 안 돌고 usage가 null이다."""
    pages.get(BLOG).respond(html=JSONLD_HTML)

    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": BLOG})

    assert res.status_code == 200
    body = res.json()
    assert body["ingredients"] == ["김치 300g", "돼지고기 200g", "두부 1모"]
    assert body["usage"] is None
    assert fake_llm.extracted_titles == []
    assert fake_llm.content_calls == []
    assert fake_llm.video_urls == []


async def test_jsonld_없으면_본문_경로로_LLM_호출(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
    public_dns: None,
) -> None:
    pages.get(BLOG).respond(html=PLAIN_HTML)

    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": BLOG})

    assert res.status_code == 200
    body = res.json()
    assert body["ingredients"] == CONTENT_EXTRACTION
    assert body["usage"] is not None
    # 본문 훅에 제목과 태그 벗긴 페이지 텍스트가 닿았다.
    [(title, content)] = fake_llm.content_calls
    assert title == "김치찌개"
    assert "김치찌개 황금 레시피" in content
    assert "<h1>" not in content
    assert fake_llm.extracted_titles == []


async def test_fetch_연결_거부는_제목_폴백(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
    public_dns: None,
) -> None:
    """AC: 어느 단이 실패해도 저장 성공률은 현행 이상 — 최종 단은 기존 제목 추론이다."""
    pages.get(BLOG).mock(side_effect=httpx.ConnectError("connection refused"))

    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": BLOG})

    assert res.status_code == 200
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.extracted_titles == ["김치찌개"]
    assert fake_llm.content_calls == []


async def test_SSRF_차단은_제목_폴백_아웃바운드_0건(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """사설 대상은 fetch 자체가 안 나간다 — 가드 차단도 502가 아니라 제목 폴백이다."""

    async def private_resolve(host: str) -> set[str]:
        return {"10.0.0.5"}

    monkeypatch.setattr(urlguard, "resolve_host", private_resolve)
    route = pages.get(BLOG).respond(html=JSONLD_HTML)

    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": BLOG})

    assert res.status_code == 200
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert not route.called
    assert fake_llm.extracted_titles == ["김치찌개"]


async def test_html_아닌_응답은_제목_폴백(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
    public_dns: None,
) -> None:
    pages.get(BLOG).respond(content=b"%PDF-1.4", content_type="application/pdf")

    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": BLOG})

    assert res.status_code == 200
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]


async def test_유튜브_URL은_영상_직독_단_fetch_없음(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
) -> None:
    """유튜브는 페이지를 긁지 않는다 — respx에 라우트가 없어 fetch가 나가면 시끄럽게 실패한다."""
    url = "https://youtu.be/tDlw8yMg9NY"

    res = await authed.post(EXTRACT, json={"title": "김치볶음밥", "url": url})

    assert res.status_code == 200
    assert res.json()["ingredients"] == VIDEO_EXTRACTION
    assert fake_llm.video_urls == [url]
    assert fake_llm.extracted_titles == []


async def test_유튜브_URL의_자격증명은_벗겨져서_영상_단에_닿는다(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
) -> None:
    """자격증명 박힌 유튜브 URL — file_uri로 통째 가면 제3자(Gemini) 유출이다. host만 남긴다."""
    res = await authed.post(
        EXTRACT,
        json={"title": "김치볶음밥", "url": "https://user:secret@youtu.be/tDlw8yMg9NY"},
    )

    assert res.status_code == 200
    assert res.json()["ingredients"] == VIDEO_EXTRACTION
    assert fake_llm.video_urls == ["https://youtu.be/tDlw8yMg9NY"]


async def test_유튜브_위장_userinfo_호스트는_영상_단으로_안_간다(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
) -> None:
    """youtu.be@evil.com — hostname은 evil.com이라 web 단이고, urlguard가 userinfo를 fetch 전에
    거부해 제목 폴백한다. respx에 라우트가 없어 아웃바운드가 나가면 시끄럽게 실패한다."""
    res = await authed.post(
        EXTRACT, json={"title": "김치찌개", "url": "https://youtu.be@evil.com/watch"}
    )

    assert res.status_code == 200
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.video_urls == []
    assert fake_llm.content_calls == []
    assert fake_llm.extracted_titles == ["김치찌개"]


async def test_url_없으면_기존_제목_추론_그대로(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    res = await authed.post(EXTRACT, json={"title": "김치찌개"})

    assert res.status_code == 200
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.extracted_titles == ["김치찌개"]
    assert fake_llm.video_urls == []
    assert fake_llm.content_calls == []


# ── 강등 수리 회귀 — 적대 검증 R1·R2·R3 ─────────────────────────────────────


async def test_유튜브_영상_직독_실패는_제목_폴백_blog_fetch_없음(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
    public_dns: None,
) -> None:
    """R1: 비공개·삭제 영상 등 직독 실패는 502가 아니라 제목 강등 — 유튜브 페이지 fetch도 안 나간다(봇 차단 본문 오염)."""
    url = "https://youtu.be/private123"
    fake_llm.video_failure = UpstreamLLMError("file_uri 접근 불가")
    route = pages.get(url).respond(html=PLAIN_HTML)

    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": url})

    assert res.status_code == 200
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.extracted_titles == ["김치찌개"]
    assert fake_llm.content_calls == []
    assert not route.called


async def test_유튜브_강등_후_LLM_자체_다운이면_502_유지(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService, pages: respx.Router
) -> None:
    """R1: 강등된 제목 단도 UpstreamLLMError면 LLM 자체 다운 — 기존 정책 그대로 502."""
    fake_llm.failure = UpstreamLLMError("LLM 다운")

    res = await authed.post(
        EXTRACT, json={"title": "김치찌개", "url": "https://youtu.be/x"}
    )

    assert res.status_code == 502


@pytest.mark.parametrize(
    "bad_url",
    [
        "http://[::1",  # 괄호 불균형 IPv6 — urlsplit ValueError('Invalid IPv6 URL')
        "http://exa[mple.com/recipe",  # '[' 포함 오타
    ],
)
async def test_파싱_불가_URL은_500_아닌_제목_폴백(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService, bad_url: str
) -> None:
    """R2: classify·경로 로그의 urlsplit ValueError가 500이 되면 안 된다 — 제목 단으로 저장 성공."""
    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": bad_url})

    assert res.status_code == 200
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.extracted_titles == ["김치찌개"]
    assert fake_llm.content_calls == []
    assert fake_llm.video_urls == []


async def test_파싱_불가_URL_레시피_저장_성공(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    """R2: 저장 경로(add)도 같은 사다리 — 파싱 불가 URL로도 저장은 성공한다."""
    res = await authed.post(RECIPES, json={"url": "http://[::1", "title": "김치찌개"})

    assert res.status_code == 201
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.extracted_titles == ["김치찌개"]


async def test_IDNA_인코딩_불가_호스트는_제목_폴백(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    """R3: 라벨 64자 초과 호스트 — getaddrinfo의 UnicodeError가 새어나가 500이 되면 안 된다."""
    url = f"http://{'a' * 64}.example/recipe"

    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": url})

    assert res.status_code == 200
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.extracted_titles == ["김치찌개"]
    assert fake_llm.content_calls == []


# ── 구조적 강등 마감 — 좁은 except 목록 밖 예외도 전부 제목 단으로 ───────────


async def test_범위초과_포트_URL도_레시피_저장_성공(
    authed: httpx.AsyncClient, fake_llm: FakeLLMService
) -> None:
    """공개 IP 리터럴 + 범위초과 포트 — anyio가 OverflowError를 ExceptionGroup으로 던져
    httpx.HTTPError 목록을 뚫고 500이 되던 사례. 실 재현은 test_llm_ingest의 fetch_page 유닛이 맡고,
    여기서는 저장 경로가 제목 단으로 강등돼 201이 되는 계약을 못박는다."""
    url = "http://93.184.216.34:99999999/recipe"

    res = await authed.post(RECIPES, json={"url": url, "title": "김치찌개"})

    assert res.status_code == 201
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.extracted_titles == ["김치찌개"]
    assert fake_llm.content_calls == []


async def test_깊은_중첩_jsonld는_500_아닌_제목_폴백(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
    public_dns: None,
) -> None:
    """json.loads의 RecursionError(ValueError 아님)도 강등된다 — web 단 통째 제목 강등."""
    deep = (
        '<html><head><script type="application/ld+json">'
        + "[" * 40_000
        + "]" * 40_000
        + "</script></head><body>본문</body></html>"
    )
    pages.get(BLOG).respond(html=deep)

    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": BLOG})

    assert res.status_code == 200
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.extracted_titles == ["김치찌개"]
    assert fake_llm.content_calls == []


async def test_결정적_단의_미지_예외는_전부_제목_강등(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """대표 회귀 방지 — 계약은 예외 타입 열거가 아니라 광범위 강등이다(미래의 예외 포함)."""

    async def boom(url: str) -> str:
        raise RuntimeError("미래의 미지 예외")

    monkeypatch.setattr(ingest, "fetch_page", boom)

    res = await authed.post(RECIPES, json={"url": BLOG, "title": "김치찌개"})

    assert res.status_code == 201
    assert res.json()["ingredients"] == EXTRACTIONS["김치찌개"]
    assert fake_llm.extracted_titles == ["김치찌개"]


async def test_본문_단_LLM_다운은_강등_없이_502(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
    public_dns: None,
) -> None:
    """대조군 — UpstreamLLMError만 강등을 통과한다. 제목 단으로 내려가지 않고 그대로 502."""
    pages.get(BLOG).respond(html=PLAIN_HTML)
    fake_llm.content_failure = UpstreamLLMError("LLM 다운")

    res = await authed.post(EXTRACT, json={"title": "김치찌개", "url": BLOG})

    assert res.status_code == 502
    assert fake_llm.extracted_titles == []


# ── POST /recipes 가 url을 사다리에 전달한다 ─────────────────────────────────


async def test_레시피_저장이_jsonld_추출을_탄다(
    authed: httpx.AsyncClient,
    fake_llm: FakeLLMService,
    pages: respx.Router,
    public_dns: None,
) -> None:
    """저장 경로도 같은 seam을 지난다 — 블로그 URL이면 JSON-LD 재료가 그대로 항목에 남는다."""
    pages.get(BLOG).respond(html=JSONLD_HTML)

    res = await authed.post(RECIPES, json={"url": BLOG, "title": "김치찌개"})

    assert res.status_code == 201
    assert res.json()["ingredients"] == ["김치 300g", "돼지고기 200g", "두부 1모"]
    assert fake_llm.extracted_titles == []
    assert fake_llm.content_calls == []
