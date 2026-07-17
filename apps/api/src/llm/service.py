# LLM 경계 — 인식·추출·매칭의 유일한 seam. 테스트는 여기에만 결정적 페이크를 주입한다 (스펙 #96)
from abc import ABC, abstractmethod
from collections.abc import Sequence

from pydantic import BaseModel, ConfigDict, Field

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


class BaseLLMService(ABC):
    """프록시 엔드포인트는 3개지만 seam은 1개다 — 구현은 Gemini(운영)와 FakeLLMService(테스트)뿐이다.

    인식·추출은 후처리가 없어 wire 모델을 그대로 반환하고, 매칭만 점수 없는 outcome을 반환한다.
    """

    @abstractmethod
    async def recognize(self, image_jpeg: bytes) -> RecognizeResponse: ...

    @abstractmethod
    async def extract(self, title: str) -> ExtractResponse: ...

    @abstractmethod
    async def match(
        self, ingredients: Sequence[str], recipes: Sequence[MatchRecipe]
    ) -> MatchOutcome: ...
