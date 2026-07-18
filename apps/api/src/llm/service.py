# LLM 경계 — 인식·추출·매칭의 유일한 seam. 테스트는 여기에만 결정적 페이크를 주입한다 (스펙 #96)
import logging
from abc import ABC, abstractmethod
from collections.abc import Sequence
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field

from src.llm import ingest
from src.llm.exceptions import UpstreamLLMError
from src.llm.schemas import (
    ExtractResponse,
    LLMUsage,
    MatchRecipe,
    MissingIngredient,
    RecognizeResponse,
    SuggestionSource,
)


class MatchCandidate(BaseModel):
    """Gemini가 낸 후보 원형. required는 산식 입력이고 wire로 나가지 않는다."""

    model_config = ConfigDict(frozen=True)

    menu: str
    source: SuggestionSource
    missing: list[MissingIngredient]
    reason: str
    required: list[str] = Field(default_factory=list)


class MatchOutcome(BaseModel):
    """매칭 seam의 반환 — 점수가 없다. 점수는 서버 산식(scoring.py)이 붙인다."""

    model_config = ConfigDict(frozen=True)

    candidates: list[MatchCandidate]
    usage: LLMUsage


logger = logging.getLogger(__name__)


def _log_extract_path(path: str, url: str | None) -> None:
    """추출 경로 계측 — host만 남긴다(전체 URL 금지, §12 최소수집)."""
    try:
        # 괄호 불균형 IPv6 등 파싱 불가 URL에서 ValueError — 로그가 본 흐름을 죽이면 안 된다
        host = urlsplit(url).hostname if url else None
    except ValueError:
        host = None
    logger.info("extract path=%s host=%s", path, host)


class BaseLLMService(ABC):
    """프록시 엔드포인트는 3개지만 seam은 1개다 — 구현은 Gemini(운영)와 FakeLLMService(테스트)뿐이다.

    인식·추출은 후처리가 없어 wire 모델을 그대로 반환하고, 매칭만 점수 없는 outcome을 반환한다.

    추출 사다리(#123)는 seam의 공통 구현이다 — 결정적 단(유튜브 판별·fetch·JSON-LD·본문 텍스트)이
    여기서 돌고, LLM이 필요한 단만 추상 훅으로 내려간다. 그래서 페이크를 꽂아도 사다리는 실물이 돈다.
    """

    async def extract(self, title: str, url: str | None = None) -> ExtractResponse:
        """추출 사다리 — ①유튜브 영상 직독 ②JSON-LD Recipe(LLM 무호출·usage None) ③본문 텍스트 ④제목 추론.

        구조적 강등 — 결정적 단(분류·fetch·JSON-LD·본문 파싱)의 실패는 예외 타입을 열거하지 않고
        전부 다음 단(궁극적으로 제목 추론)으로 강등한다. 저장 성공률은 현행 이상.
        오직 LLM 호출 자체의 다운(UpstreamLLMError)만 기존 정책 그대로 전파한다(레시피 저장은 502·미저장).
        """
        try:
            kind = ingest.classify(url) if url is not None else None
        except Exception:
            # 분류 자체가 죽어도 사다리는 멈추지 않는다 — 제목 단 직행.
            kind = None
        if url is not None and kind == "youtube":
            _log_extract_path("youtube", url)
            try:
                # userinfo 제거 — file_uri로 URL이 통째 제3자(Gemini)에 가므로 자격증명을 벗긴다.
                return await self.extract_from_video(ingest.strip_userinfo(url))
            except Exception as exc:
                # 이 단의 모든 실패는 제목 단으로 강등한다 — UpstreamLLMError 포함(영상 접근
                # 불가: 비공개·삭제·채널 URL 등과 LLM 다운이 같은 타입으로 나와 구분 불가).
                # blog-fetch 단은 건너뛴다 — 유튜브 URL fetch는 봇 차단 페이지 본문이 LLM에 오염 유입된다.
                # 강등된 제목 단이 다시 UpstreamLLMError를 던지면(=LLM 자체 다운) 그대로 502다.
                _log_extract_path(f"youtube_fallback_title:{type(exc).__name__}", url)
        if url is not None and kind == "web":
            try:
                extracted = await self._extract_from_web(title, url)
            except UpstreamLLMError:
                # 본문 단 LLM 호출 자체의 다운 — 강등 대상이 아니라 그대로 502다.
                raise
            except Exception as exc:
                # 광범위 강등 — 좁은 예외 목록의 두더지잡기를 끝낸다. 범위초과 포트의
                # OverflowError(anyio ExceptionGroup)·깊은 중첩 JSON-LD의 RecursionError 등
                # 목록 밖·미래의 예외까지 전부 제목 단으로 내린다. BaseException(취소·인터럽트)은 잡지 않는다.
                _log_extract_path(f"web_fallback_title:{type(exc).__name__}", url)
                extracted = None
            if extracted is not None:
                return extracted
        _log_extract_path("title", url)
        return await self.extract_from_title(title)

    async def _extract_from_web(self, title: str, url: str) -> ExtractResponse | None:
        """web 단 — fetch→JSON-LD→본문 LLM. 예외 처리는 extract의 강등 블록이 맡는다(여기서 좁게 잡지 않는다).

        None = 이 단이 재료를 못 냈다(본문 텍스트가 빈 결정적 미스) — 호출자가 제목 단으로 간다.
        """
        html = await ingest.fetch_page(url)
        ingredients = ingest.parse_jsonld_recipe(html)
        if ingredients is not None:
            _log_extract_path("jsonld", url)
            return ExtractResponse(ingredients=ingredients, usage=None)
        content = ingest.html_to_text(html)
        if not content:
            return None
        _log_extract_path("content", url)
        return await self.extract_from_content(title, content)

    @abstractmethod
    async def recognize(self, image_jpeg: bytes) -> RecognizeResponse: ...

    @abstractmethod
    async def extract_from_title(self, title: str) -> ExtractResponse:
        """제목 추론 — 사다리 최종 단(기존 #101 경로)."""

    @abstractmethod
    async def extract_from_video(self, url: str) -> ExtractResponse:
        """유튜브 영상 직독 — Gemini file_uri. UpstreamLLMError는 extract가 제목 단으로 강등한다."""

    @abstractmethod
    async def extract_from_content(self, title: str, content: str) -> ExtractResponse:
        """페이지 본문 텍스트 기반 추출 — JSON-LD가 없을 때."""

    @abstractmethod
    async def match(
        self, ingredients: Sequence[str], recipes: Sequence[MatchRecipe]
    ) -> MatchOutcome: ...
