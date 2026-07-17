# og:image fetch 서비스 — 수동 리다이렉트 추적·스트리밍 상한·전체 데드라인 (#102)
import asyncio
import codecs
from urllib.parse import urljoin, urlsplit

import httpx

from src.ogimage import guard
from src.ogimage.exceptions import OgImageUnresolvable
from src.ogimage.parser import OgImageParser

# 상수(설정 아님) — 필수 Settings 필드는 export_openapi·CI env·conftest 3곳 플레이스홀더를 강제한다
# per-op(connect/read/write 각각) 타임아웃 — 요청 전체 상한은 아래 데드라인이 맡는다
TIMEOUT = httpx.Timeout(5.0)
# slowloris 방어 — per-op 타임아웃은 찔끔찔끔 주는 서버를 못 끊는다
TOTAL_DEADLINE_SECONDS = 10.0
# 압축 해제 후 기준(안전한 방향) — og 메타는 head에 있으니 여기서 잘라 부분 파싱하면 된다
MAX_BYTES = 1_048_576
MAX_REDIRECTS = 5
CHUNK_SIZE = 65_536

_ALLOWED_SCHEMES = ("http", "https")


async def fetch_og_image(url: str) -> str | None:
    """출처 페이지의 og:image URL. 모든 fetch 실패는 부재(None)로 흡수한다 — 500이 아니다.

    OgImageBlocked(SSRF)만 통과시켜 라우터가 400으로 바꾼다.
    """
    try:
        async with asyncio.timeout(TOTAL_DEADLINE_SECONDS):
            return await _fetch(url)
    except (TimeoutError, httpx.HTTPError, OgImageUnresolvable):
        return None


async def _fetch(url: str) -> str | None:
    async with httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=False) as client:
        for _ in range(MAX_REDIRECTS + 1):
            # hop마다 재검증 — 공개 URL이 사설 대상으로 리다이렉트하는 게 SSRF의 정석이다
            await guard.ensure_public_url(url)
            async with client.stream("GET", url) as response:
                # 301·302·303·307·308 + Location 있는 경우만 — is_redirect(모든 3xx)가 아니다
                if response.has_redirect_location:
                    if response.next_request is None:
                        return None
                    url = str(response.next_request.url)
                    continue
                if not response.is_success:
                    return None
                if "html" not in response.headers.get("content-type", "").lower():
                    return None
                return await _extract_from_stream(response)
        return None  # 리다이렉트 한도 초과 — 공격이 아니라 fetch 실패


async def _extract_from_stream(response: httpx.Response) -> str | None:
    """상한까지만 읽으며 청크 단위로 파싱한다 — 찾는 즉시, 또는 상한에서 중단."""
    try:
        decoder_factory = codecs.getincrementaldecoder(
            response.charset_encoding or "utf-8"
        )
    except LookupError:
        decoder_factory = codecs.getincrementaldecoder("utf-8")
    # incremental — 청크 경계가 멀티바이트(UTF-8·EUC-KR)를 쪼개도 깨지지 않는다
    decoder = decoder_factory("replace")
    parser = OgImageParser()
    received = 0
    # ByteChunker가 재분할하므로 mock의 단일 청크 응답에서도 상한 중단이 실제로 돈다
    async for chunk in response.aiter_bytes(chunk_size=CHUNK_SIZE):
        received += len(chunk)
        overshoot = received - MAX_BYTES
        if overshoot > 0:
            chunk = chunk[: len(chunk) - overshoot]
        parser.feed(decoder.decode(chunk))
        if parser.og_image is not None or received >= MAX_BYTES:
            break
    return _absolutize(parser.og_image, str(response.request.url))


def _absolutize(content: str | None, final_url: str) -> str | None:
    """상대 content를 최종(리다이렉트 후) URL 기준으로 절대화. http(s)가 아니면 부재."""
    if content is None:
        return None
    absolute = urljoin(final_url, content)
    if urlsplit(absolute).scheme not in _ALLOWED_SCHEMES:
        return None
    return absolute
