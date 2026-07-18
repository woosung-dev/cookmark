# URL 추출 사다리의 결정적 단 — 유튜브 판별·페이지 fetch(SSRF 가드)·JSON-LD Recipe·본문 텍스트 (#123)
import asyncio
import codecs
import json
from collections.abc import Iterator
from html.parser import HTMLParser
from typing import Literal
from urllib.parse import urlsplit, urlunsplit

import httpx

from src.common import urlguard
from src.llm.exceptions import IngestFetchError

# 상수(설정 아님) — ogimage/service.py의 fetch 패턴을 미러한다(#102 검증식 재사용)
# per-op(connect/read/write 각각) 타임아웃 — 요청 전체 상한은 아래 데드라인이 맡는다
TIMEOUT = httpx.Timeout(5.0)
# slowloris 방어 — per-op 타임아웃은 찔끔찔끔 주는 서버를 못 끊는다
TOTAL_DEADLINE_SECONDS = 10.0
# 응답 상한 2MB — 레시피 본문은 head가 아니라 body에 있어 og:image(1MB)보다 넉넉히 잡는다
MAX_BYTES = 2_097_152
MAX_REDIRECTS = 5
CHUNK_SIZE = 65_536
# 브라우저 UA — 레시피 블로그 다수가 기본 python-httpx UA를 403으로 거른다
BROWSER_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)
# 본문 텍스트 상한 — 프롬프트 토큰 폭주 방지(레시피 재료는 본문 앞쪽에 몰린다)
TEXT_LIMIT = 8_000
# JSON-LD 결정적 경로의 온건한 상한 — 악의적 recipeIngredient가 DB·응답에 그대로 실리는 것 방지.
# LLM 경로는 모델 출력이 자연 상한이라 이 경로만 필요하다.
MAX_JSONLD_INGREDIENTS = 64
MAX_JSONLD_INGREDIENT_CHARS = 100

# 유튜브 호스트 정확 일치 — youtube.com.evil.com 류 서픽스 위장을 막는다. /shorts/는 경로라 호스트로 충분하다.
YOUTUBE_HOSTS = frozenset(
    {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}
)

UrlKind = Literal["youtube", "web", "invalid"]


def classify(url: str) -> UrlKind:
    """유튜브 URL이면 "youtube"(Gemini file_uri 직독 대상), 파싱 불가면 "invalid"(제목 단 직행), 그 외 "web"."""
    try:
        parts = urlsplit(url)
        host = (parts.hostname or "").lower()
    except ValueError:
        # 괄호 불균형 IPv6('http://[::1') 등 — 분류 불가는 fetch 없이 곧장 제목 추론 단으로 보낸다
        return "invalid"
    if parts.scheme in urlguard.ALLOWED_SCHEMES and host in YOUTUBE_HOSTS:
        return "youtube"
    return "web"


def strip_userinfo(url: str) -> str:
    """netloc의 userinfo(user:pass@)를 제거해 재조립한다 — 자격증명이 제3자(Gemini)로 새는 것을 막는다.

    urlguard의 userinfo 거부는 fetch 경로에만 있어 유튜브 단(file_uri 직송)에는 닿지 않는다 — 이 헬퍼가
    그 구멍을 막는다. 파싱 불가(ValueError)면 원본 반환 — 유튜브 단 전용이고 classify가 이미 유효 host를
    보장하므로 실무상 도달하지 않는다.
    """
    try:
        parts = urlsplit(url)
        if "@" not in parts.netloc:
            return url
        netloc = parts.hostname or ""
        if parts.port is not None:
            netloc = f"{netloc}:{parts.port}"
    except ValueError:
        return url
    return urlunsplit((parts.scheme, netloc, parts.path, parts.query, parts.fragment))


async def fetch_page(url: str) -> str:
    """페이지 HTML 텍스트(상한까지). 모든 실패는 IngestFetchError 하나로 — 호출자는 다음 단으로 강등한다."""
    try:
        async with asyncio.timeout(TOTAL_DEADLINE_SECONDS):
            return await _fetch(url)
    except IngestFetchError:
        raise
    except Exception as exc:
        # 광범위 변환 — 예외 타입 열거(httpx.HTTPError·UrlBlocked·UnicodeError…)는 두더지잡기였다.
        # 범위초과 포트의 OverflowError(anyio가 ExceptionGroup으로 감싼다)처럼 목록 밖 예외가
        # 새어나가 500이 되는 것을 구조적으로 막는다. BaseException(취소·인터럽트)은 잡지 않는다.
        raise IngestFetchError(f"페이지 fetch 실패: {type(exc).__name__}") from exc


async def _fetch(url: str) -> str:
    async with httpx.AsyncClient(
        timeout=TIMEOUT,
        follow_redirects=False,
        headers={"User-Agent": BROWSER_USER_AGENT},
    ) as client:
        for _ in range(MAX_REDIRECTS + 1):
            # hop마다 재검증 — 공개 URL이 사설 대상으로 리다이렉트하는 게 SSRF의 정석이다
            await urlguard.ensure_public_url(url)
            async with client.stream("GET", url) as response:
                # 301·302·303·307·308 + Location 있는 경우만 — is_redirect(모든 3xx)가 아니다
                if response.has_redirect_location:
                    if response.next_request is None:
                        raise IngestFetchError("리다이렉트 Location 조립 실패")
                    url = str(response.next_request.url)
                    continue
                if not response.is_success:
                    raise IngestFetchError(f"HTTP {response.status_code}")
                if "html" not in response.headers.get("content-type", "").lower():
                    raise IngestFetchError("HTML 아님")
                return await _read_capped(response)
        raise IngestFetchError("리다이렉트 한도 초과")


async def _read_capped(response: httpx.Response) -> str:
    """상한까지만 읽어 디코드한다 — incremental이라 청크 경계의 멀티바이트도 깨지지 않는다."""
    try:
        decoder_factory = codecs.getincrementaldecoder(
            response.charset_encoding or "utf-8"
        )
    except LookupError:
        decoder_factory = codecs.getincrementaldecoder("utf-8")
    decoder = decoder_factory("replace")
    pieces: list[str] = []
    received = 0
    # ByteChunker가 재분할하므로 mock의 단일 청크 응답에서도 상한 중단이 실제로 돈다
    async for chunk in response.aiter_bytes(chunk_size=CHUNK_SIZE):
        received += len(chunk)
        overshoot = received - MAX_BYTES
        if overshoot > 0:
            chunk = chunk[: len(chunk) - overshoot]
        pieces.append(decoder.decode(chunk))
        if received >= MAX_BYTES:
            break
    return "".join(pieces)


class _JsonLdCollector(HTMLParser):
    """<script type="application/ld+json"> 블록의 원문을 전부 모은다."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.blocks: list[str] = []
        self._buffer: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "script":
            return
        script_type = next((v for k, v in attrs if k == "type"), None) or ""
        # charset 등 파라미터가 붙는 표기까지 허용 — 값 정확 일치만 보면 실 페이지를 놓친다
        if script_type.strip().lower().startswith("application/ld+json"):
            self._buffer = []

    def handle_data(self, data: str) -> None:
        if self._buffer is not None:
            self._buffer.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self._buffer is not None:
            self.blocks.append("".join(self._buffer))
            self._buffer = None


def _walk_nodes(data: object) -> Iterator[dict[str, object]]:
    """JSON-LD 최상위·리스트·@graph 안의 노드를 평평하게 순회한다."""
    if isinstance(data, list):
        for item in data:
            yield from _walk_nodes(item)
    elif isinstance(data, dict):
        yield data
        graph = data.get("@graph")
        if isinstance(graph, list):
            for item in graph:
                yield from _walk_nodes(item)


def _is_recipe(node: dict[str, object]) -> bool:
    node_type = node.get("@type")
    if isinstance(node_type, str):
        return node_type == "Recipe"
    if isinstance(node_type, list):
        return "Recipe" in node_type
    return False


def parse_jsonld_recipe(html: str) -> list[str] | None:
    """@type=Recipe 노드의 recipeIngredient — 비어 있지 않으면 그 목록, 아니면 None(다음 단으로)."""
    collector = _JsonLdCollector()
    collector.feed(html)
    for block in collector.blocks:
        try:
            data = json.loads(block)
        except ValueError:
            continue
        for node in _walk_nodes(data):
            if not _is_recipe(node):
                continue
            raw = node.get("recipeIngredient")
            if not isinstance(raw, list):
                continue
            ingredients = [
                item.strip()[:MAX_JSONLD_INGREDIENT_CHARS]
                for item in raw
                if isinstance(item, str) and item.strip()
            ][:MAX_JSONLD_INGREDIENTS]
            if ingredients:
                return ingredients
    return None


class _TextExtractor(HTMLParser):
    """태그를 벗기고 텍스트만 모은다 — script·style 내용물은 본문이 아니다."""

    _SKIPPED = frozenset({"script", "style"})

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.pieces: list[str] = []
        self._skip_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self._SKIPPED:
            self._skip_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in self._SKIPPED and self._skip_depth > 0:
            self._skip_depth -= 1

    def handle_data(self, data: str) -> None:
        if self._skip_depth == 0:
            self.pieces.append(data)


def html_to_text(html: str) -> str:
    """본문 텍스트 — 공백 축약 후 TEXT_LIMIT 상한. 빈 문자열이면 호출자는 다음 단으로 간다."""
    extractor = _TextExtractor()
    extractor.feed(html)
    collapsed = " ".join("".join(extractor.pieces).split())
    return collapsed[:TEXT_LIMIT]
