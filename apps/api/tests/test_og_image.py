# og:image 프록시 관통 테스트 — 세션·SSRF·타임아웃·상한·부재 응답 (#102 AC 전량)
import asyncio
from collections.abc import AsyncIterator, Iterator

import httpx
import pytest
import respx

from src.auth.oidc import Provider
from src.ogimage import guard, service
from tests.idp import FakeIdp

OG_IMAGE = "/api/v1/og-image"
PAGE = "https://recipe.example/post/123"


@pytest.fixture
def pages() -> Iterator[respx.Router]:
    """출처 페이지 mock 전용 respx 컨텍스트 — idp 픽스처와 별개 라우터로 공존한다(fall-through)."""
    with respx.mock(assert_all_called=False) as router:
        yield router


@pytest.fixture
def public_dns(monkeypatch: pytest.MonkeyPatch) -> None:
    """테스트 호스트네임을 공개 IP로 해석 — 가드의 실 DNS를 결정적 페이크로 바꾼다."""

    async def fake_resolve(host: str) -> set[str]:
        return {"93.184.216.34"}

    monkeypatch.setattr(guard, "resolve_host", fake_resolve)


def html_with_og_image(content: str) -> str:
    return f'<html><head><meta property="og:image" content="{content}"></head></html>'


async def login(client: httpx.AsyncClient, idp: FakeIdp) -> None:
    response = await idp.login(client, Provider.KAKAO, sub="og-image-user")
    assert response.status_code == 200, response.text


async def test_og_image_found(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    """AC: og:image 있는 페이지 → 이미지 URL 반환."""
    await login(client, idp)
    pages.get(PAGE).respond(
        html=html_with_og_image("https://img.recipe.example/food.jpg")
    )

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": "https://img.recipe.example/food.jpg"}


async def test_relative_og_image_and_relative_redirect(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    """상대 Location 추적 + 상대 og:image content를 최종 URL 기준으로 절대화한다."""
    await login(client, idp)
    pages.get(PAGE).respond(302, headers={"location": "/moved/456"})
    pages.get("https://recipe.example/moved/456").respond(
        html=html_with_og_image("/img/food.jpg")
    )

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": "https://recipe.example/img/food.jpg"}


async def test_no_og_image_returns_null(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    """AC: og:image 없음 → 명시적 부재 응답, 500 아님."""
    await login(client, idp)
    pages.get(PAGE).respond(html="<html><head><title>레시피</title></head></html>")

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": None}


async def test_non_html_content_type_returns_null(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    """AC: 비HTML → 부재. 이미지 바이트를 HTML로 파싱하려 들지 않는다."""
    await login(client, idp)
    pages.get(PAGE).respond(content=b"\x89PNG...", content_type="image/png")

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": None}


async def test_upstream_error_status_returns_null(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    await login(client, idp)
    pages.get(PAGE).respond(500)

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": None}


async def test_timeout_returns_null(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    """AC: 타임아웃 → 부재 응답, 500 아님."""
    await login(client, idp)
    pages.get(PAGE).mock(side_effect=httpx.TimeoutException)

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": None}


class _DripStream(httpx.AsyncByteStream):
    """찔끔찔끔 주는 서버 — 첫 청크 뒤 오래 멈춘다. og:image는 멈춤 뒤에야 온다."""

    async def __aiter__(self) -> AsyncIterator[bytes]:
        yield b"<html><head>"
        await asyncio.sleep(0.5)
        yield html_with_og_image("https://img.recipe.example/slow.jpg").encode()


async def test_total_deadline_cuts_slow_stream(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    pages: respx.Router,
    public_dns: None,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """AC: 타임아웃 동작 — per-op 타임아웃이 못 끊는 slowloris를 전체 데드라인이 실제로 끊는다."""
    await login(client, idp)
    monkeypatch.setattr(service, "TOTAL_DEADLINE_SECONDS", 0.05)
    pages.get(PAGE).mock(
        return_value=httpx.Response(
            200, headers={"content-type": "text/html"}, stream=_DripStream()
        )
    )

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    # og:image는 멈춤 뒤 청크에만 있다 — null은 데드라인이 스트림을 중도에 끊었다는 증거다
    assert res.json() == {"image_url": None}


async def test_connect_error_returns_null(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    await login(client, idp)
    pages.get(PAGE).mock(side_effect=httpx.ConnectError)

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": None}


async def test_unresolvable_host_returns_null(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    pages: respx.Router,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """NXDOMAIN은 정책 위반이 아니다 — 400이 아니라 부재."""
    await login(client, idp)

    async def fake_resolve(host: str) -> set[str]:
        return set()

    monkeypatch.setattr(guard, "resolve_host", fake_resolve)

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": None}
    assert len(pages.calls) == 0


async def test_og_image_beyond_size_cap_returns_null(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    """AC: 응답 크기 상한 — 상한 밖의 og:image는 읽지 않는다(잘린 만큼만 파싱)."""
    await login(client, idp)
    padding = "p" * (service.MAX_BYTES + 10_000)
    pages.get(PAGE).respond(
        html=f"<html><head>{padding}"
        + html_with_og_image("https://img.recipe.example/late.jpg")
    )

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": None}


async def test_og_image_within_cap_of_large_body_found(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    """상한보다 큰 페이지라도 og:image가 head(상한 안)에 있으면 잡는다 — 부분 파싱 증명."""
    await login(client, idp)
    body = html_with_og_image("https://img.recipe.example/early.jpg") + "b" * (
        service.MAX_BYTES + 10_000
    )
    pages.get(PAGE).respond(html=body)

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 200
    assert res.json() == {"image_url": "https://img.recipe.example/early.jpg"}


@pytest.mark.parametrize(
    "target",
    [
        "http://127.0.0.1/recipe",
        "http://10.0.0.1/recipe",
        "http://169.254.169.254/latest/meta-data/",
        "http://[::1]/recipe",
        "http://[::ffff:127.0.0.1]/recipe",
        "http://0.0.0.0/recipe",
        "http://2130706433/recipe",  # 10진 IP — pydantic이 127.0.0.1로 정규화(실측)
    ],
)
async def test_private_target_rejected_before_any_fetch(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    pages: respx.Router,
    target: str,
) -> None:
    """AC: 사설 IP·localhost 직접 요청 거부 — 패킷이 나가기 전에 400."""
    await login(client, idp)

    res = await client.get(OG_IMAGE, params={"url": target})

    assert res.status_code == 400
    assert len(pages.calls) == 0  # fetch 자체가 없었다


async def test_hostname_resolving_to_private_rejected(
    client: httpx.AsyncClient,
    idp: FakeIdp,
    pages: respx.Router,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """내부 호스트네임(DNS가 사설로 해석)도 같은 400 — IP 리터럴만 막는 가드가 아니다."""
    await login(client, idp)

    async def fake_resolve(host: str) -> set[str]:
        return {"10.0.0.5"}

    monkeypatch.setattr(guard, "resolve_host", fake_resolve)

    res = await client.get(OG_IMAGE, params={"url": "https://internal.example/admin"})

    assert res.status_code == 400
    assert len(pages.calls) == 0


async def test_redirect_to_private_rejected(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    """AC: 리다이렉트 경유 사설 대상 거부 — hop마다 가드가 다시 돈다."""
    await login(client, idp)
    pages.get(PAGE).respond(
        302, headers={"location": "http://169.254.169.254/latest/meta-data/"}
    )

    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 400
    assert len(pages.calls) == 1  # 첫 페이지만 fetch, 사설 대상은 안 나갔다


async def test_redirect_limit_exceeded_returns_null(
    client: httpx.AsyncClient, idp: FakeIdp, pages: respx.Router, public_dns: None
) -> None:
    """리다이렉트 한도 초과는 공격이 아니라 fetch 실패 — 부재."""
    await login(client, idp)
    for hop in range(service.MAX_REDIRECTS + 2):
        pages.get(f"https://recipe.example/r{hop}").respond(
            302, headers={"location": f"/r{hop + 1}"}
        )

    res = await client.get(OG_IMAGE, params={"url": "https://recipe.example/r0"})

    assert res.status_code == 200
    assert res.json() == {"image_url": None}


async def test_without_session_is_401(
    client: httpx.AsyncClient, pages: respx.Router
) -> None:
    """AC: 무세션 401 — 프록시 인증 정책 동일 적용. fetch도 없다."""
    res = await client.get(OG_IMAGE, params={"url": PAGE})

    assert res.status_code == 401
    assert len(pages.calls) == 0


async def test_garbage_url_is_422(client: httpx.AsyncClient, idp: FakeIdp) -> None:
    """URL 형식 검증은 pydantic 몫 — 로그인 상태여야 한다(의존성 401이 검증 422보다 먼저 뜬다)."""
    await login(client, idp)

    res = await client.get(OG_IMAGE, params={"url": "이건 URL이 아니다"})

    assert res.status_code == 422
