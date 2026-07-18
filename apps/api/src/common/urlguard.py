# 공용 SSRF 가드 — 임의 사용자 URL을 서버가 fetch하기 전, 대상이 공개 인터넷인지 판정한다 (#102 → #123 공유화)
"""사설 IP·localhost 직접 요청과 리다이렉트 경유 요청을 fetch 전에 거부한다.

판정식은 ``is_global``만으로 부족하다 — Python 3.13 실측으로 멀티캐스트(224.0.0.1 등)와
NAT64(64:ff9b::/96)가 is_global=True로 통과하는 구멍이 있어 두 플래그를 보강한다.

의식적 이월 — DNS 리바인딩 TOCTOU: 여기서 resolve한 주소와 httpx가 연결 시점에 다시
resolve하는 주소가 다를 수 있다. 완전 방어는 resolve된 IP로 직접 연결하는 커스텀
transport(+Host/SNI 유지)가 필요해 이 범위 밖이다.

#123에서 ogimage 전용이던 판정 로직을 이곳으로 옮겼다 — 소비자는 ogimage(guard.py가
re-export)와 llm/ingest 둘이고, 새 서버측 fetch는 이 가드만 쓴다.
"""

import asyncio
import ipaddress
import socket
from collections.abc import Awaitable, Callable
from urllib.parse import urlsplit

# 허용 스킴의 단일 정의 — ogimage의 og:image 절대화 검사도 이걸 쓴다(정책 드리프트 방지)
ALLOWED_SCHEMES = ("http", "https")

Resolver = Callable[[str], Awaitable[set[str]]]


class UrlBlocked(Exception):
    """SSRF 정책 위반 — 사설·루프백 등 비공개 대상, 비 http(s) 스킴, userinfo. 소비자가 상태 코드로 번역한다."""


class UrlUnresolvable(Exception):
    """호스트가 해석되지 않음 — 정책 위반이 아니라 fetch 실패다. 소비자가 부재·폴백으로 흡수한다."""


def is_public_address(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    """공개 인터넷 주소만 True. IPv4-mapped IPv6는 안쪽 IPv4 기준으로 판정한다."""
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None:
        ip = ip.ipv4_mapped
    return ip.is_global and not ip.is_multicast and not ip.is_reserved


async def resolve_host(host: str) -> set[str]:
    """호스트네임의 전체 주소 집합(A+AAAA). 미해석은 빈 집합 — 판정은 호출자 몫."""
    loop = asyncio.get_running_loop()
    try:
        infos = await loop.getaddrinfo(host, None, type=socket.SOCK_STREAM)
    except socket.gaierror:
        return set()
    return {str(info[4][0]) for info in infos}


async def ensure_public_url(url: str, *, resolver: Resolver | None = None) -> None:
    """비공개 대상이면 UrlBlocked, 미해석이면 UrlUnresolvable.

    리다이렉트 hop마다 다시 불린다 — Location은 pydantic 검증을 거치지 않으므로
    스킴·호스트 검사를 여기서 전부 다시 해야 한다.

    resolver는 ogimage/guard.py의 기존 monkeypatch 표면(guard.resolve_host)을 살리기 위한
    주입점이다 — 미지정이면 이 모듈의 resolve_host를 호출 시점에 조회한다.
    """
    parts = urlsplit(url)
    if parts.scheme not in ALLOWED_SCHEMES:
        raise UrlBlocked(url)
    # 레시피 URL에 자격증명이 실릴 일이 없다 — http://무시됨@127.0.0.1/ 류 착시를 통째 거부
    if parts.username or parts.password:
        raise UrlBlocked(url)
    host = parts.hostname
    if not host:
        raise UrlBlocked(url)

    try:
        # urlsplit이 IPv6 대괄호를 벗겨주지만, pydantic .host 등 다른 경로 대비 방어적으로 한 번 더
        literal = ipaddress.ip_address(host.strip("[]"))
    except ValueError:
        resolve = resolver if resolver is not None else resolve_host
        addresses = await resolve(host)
        if not addresses:
            raise UrlUnresolvable(host) from None
        candidates = [ipaddress.ip_address(address) for address in addresses]
    else:
        candidates = [literal]

    # 하나라도 비공개면 전체 거부 — 공개+사설 A레코드 혼합이 DNS 트릭의 정석이다
    if not all(is_public_address(candidate) for candidate in candidates):
        raise UrlBlocked(url)
