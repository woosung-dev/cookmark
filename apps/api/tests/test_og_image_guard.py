# SSRF 가드 유닛 — 공개/비공개 판정식·URL 정책·DNS 전 주소 검사 (AC: 사설 IP·localhost 거부)
import ipaddress

import pytest

from src.ogimage import guard
from src.ogimage.exceptions import OgImageBlocked, OgImageUnresolvable


@pytest.mark.parametrize(
    "address",
    ["8.8.8.8", "93.184.216.34", "2001:4860:4860::8888", "2606:4700::1111"],
)
def test_public_addresses_pass(address: str) -> None:
    assert guard.is_public_address(ipaddress.ip_address(address))


@pytest.mark.parametrize(
    "address",
    [
        "127.0.0.1",  # loopback
        "10.0.0.1",  # private
        "172.16.0.1",  # private
        "192.168.1.1",  # private
        "169.254.169.254",  # link-local — 클라우드 메타데이터
        "100.64.0.1",  # CGNAT
        "192.0.2.1",  # TEST-NET
        "224.0.0.1",  # multicast — is_global=True인 함정 (3.13 실측)
        "0.0.0.0",  # unspecified
        "255.255.255.255",  # broadcast
        "::1",  # v6 loopback
        "fe80::1",  # v6 link-local
        "fc00::1",  # v6 ULA
        "ff02::1",  # v6 multicast — is_global=True인 함정
        "::ffff:127.0.0.1",  # IPv4-mapped loopback
        "::ffff:10.0.0.1",  # IPv4-mapped private
        "64:ff9b::a00:1",  # NAT64 — is_global=True·is_reserved=True인 함정
    ],
)
def test_non_public_addresses_fail(address: str) -> None:
    assert not guard.is_public_address(ipaddress.ip_address(address))


@pytest.mark.parametrize(
    "url",
    [
        "http://127.0.0.1/recipe",
        "http://10.0.0.1/recipe",
        "http://169.254.169.254/latest/meta-data/",
        "http://[::1]/recipe",
        "http://[::ffff:127.0.0.1]/recipe",
        "http://0.0.0.0/recipe",
    ],
)
async def test_private_ip_literal_urls_are_blocked(url: str) -> None:
    with pytest.raises(OgImageBlocked):
        await guard.ensure_public_url(url)


async def test_localhost_is_blocked_via_real_resolution() -> None:
    """localhost는 IP 리터럴이 아니라 DNS 경로로 온다 — 실제 resolve로 잡히는지 본다."""
    with pytest.raises(OgImageBlocked):
        await guard.ensure_public_url("http://localhost/recipe")


@pytest.mark.parametrize("url", ["ftp://recipe.example/a", "file:///etc/passwd"])
async def test_non_http_scheme_is_blocked(url: str) -> None:
    """리다이렉트 Location은 pydantic을 안 거친다 — 가드가 스킴을 직접 막아야 한다."""
    with pytest.raises(OgImageBlocked):
        await guard.ensure_public_url(url)


async def test_userinfo_url_is_blocked() -> None:
    """레시피 URL에 자격증명이 실릴 일이 없다 — http://a@127.0.0.1/ 류 착시 통째 거부."""
    with pytest.raises(OgImageBlocked):
        await guard.ensure_public_url("http://trusted@8.8.8.8/recipe")


async def test_hostless_url_is_blocked() -> None:
    with pytest.raises(OgImageBlocked):
        await guard.ensure_public_url("http:///recipe")


async def test_hostname_resolving_to_public_passes(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fake_resolve(host: str) -> set[str]:
        return {"93.184.216.34"}

    monkeypatch.setattr(guard, "resolve_host", fake_resolve)
    await guard.ensure_public_url("https://recipe.example/post")  # 예외 없으면 통과


async def test_hostname_resolving_to_private_is_blocked(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fake_resolve(host: str) -> set[str]:
        return {"10.0.0.5"}

    monkeypatch.setattr(guard, "resolve_host", fake_resolve)
    with pytest.raises(OgImageBlocked):
        await guard.ensure_public_url("https://internal.example/admin")


async def test_mixed_public_and_private_records_are_blocked(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """공개+사설 A레코드 혼합은 DNS 트릭의 정석 — 하나라도 사설이면 전체 거부."""

    async def fake_resolve(host: str) -> set[str]:
        return {"93.184.216.34", "192.168.0.10"}

    monkeypatch.setattr(guard, "resolve_host", fake_resolve)
    with pytest.raises(OgImageBlocked):
        await guard.ensure_public_url("https://tricky.example/post")


async def test_unresolvable_hostname_raises_unresolvable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """NXDOMAIN은 정책 위반이 아니라 fetch 실패다 — 400이 아닌 부재(null)로 흘러야 한다."""

    async def fake_resolve(host: str) -> set[str]:
        return set()

    monkeypatch.setattr(guard, "resolve_host", fake_resolve)
    with pytest.raises(OgImageUnresolvable):
        await guard.ensure_public_url("https://nxdomain.example/post")


async def test_resolve_host_returns_empty_on_nxdomain() -> None:
    """.invalid TLD는 RFC 6761이 영구 미해석을 보장한다 — 실 getaddrinfo 경로 검증."""
    assert await guard.resolve_host("no-such-host.invalid") == set()
