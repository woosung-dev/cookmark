# CORS 결정적 검증 — 허용 origin은 preflight·응답 헤더 통과, 비허용은 부재 (브라우저 실차단은 수동 1회)
import httpx

from tests.conftest import ALLOWED_ORIGIN

PREFLIGHT_HEADERS = {"Access-Control-Request-Method": "GET"}


async def test_preflight_passes_for_allowed_origin(client: httpx.AsyncClient) -> None:
    res = await client.options(
        "/api/v1/health",
        headers={"Origin": ALLOWED_ORIGIN, **PREFLIGHT_HEADERS},
    )

    assert res.status_code == 200
    assert res.headers["access-control-allow-origin"] == ALLOWED_ORIGIN


async def test_preflight_rejects_unknown_origin(client: httpx.AsyncClient) -> None:
    res = await client.options(
        "/api/v1/health",
        headers={"Origin": "http://not-allowed.example", **PREFLIGHT_HEADERS},
    )

    assert "access-control-allow-origin" not in res.headers
    assert res.status_code == 400


async def test_health_response_carries_cors_header_for_allowed_origin(
    client: httpx.AsyncClient,
) -> None:
    """AC: 허용 목록에 넣은 로컬 웹 origin에서 health 200."""
    res = await client.get("/api/v1/health", headers={"Origin": ALLOWED_ORIGIN})

    assert res.status_code == 200
    assert res.headers["access-control-allow-origin"] == ALLOWED_ORIGIN
