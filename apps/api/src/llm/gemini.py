# Gemini SDK 경계 — 타임아웃·원가 산식·실패 정규화가 여기 한 곳에만 있다 (_gemini.mjs 승계 · #101)
#
# 나눠 두면 모델을 바꿀 때 한쪽만 고치게 되고, 그러면 원가 로그가 조용히 틀린다.
# 원가는 T1 #6이 파일럿 원가 판정에 쓰는 입력이라 조용히 틀리면 비싸다.
from collections.abc import Sequence
from typing import TypeVar

import httpx
from google import genai
from google.genai import errors, types
from pydantic import BaseModel, ConfigDict, ValidationError

from src.common import prompts
from src.llm.exceptions import UpstreamLLMError
from src.llm.schemas import (
    ExtractResponse,
    LLMUsage,
    MatchRecipe,
    RecognizedIngredient,
    RecognizeResponse,
)
from src.llm.service import BaseLLMService, MatchCandidate, MatchOutcome

# 호출 상한(ms — HttpOptions.timeout 단위는 밀리초다). .mjs 이식값 그대로.
# 인식은 이미지라 가장 길고, 클라이언트 컷 30초보다 짧다(G1 #8).
RECOGNIZE_TIMEOUT_MS = 28_000
EXTRACT_TIMEOUT_MS = 15_000
MATCH_TIMEOUT_MS = 20_000


class _RecognitionPayload(BaseModel):
    """인식 구조화 출력 — P1에서 확정된 형태(스펙 #13). low_quality는 실패 4종 중 저품질 판별용."""

    model_config = ConfigDict(frozen=True)

    ingredients: list[RecognizedIngredient]
    low_quality: bool = False


class _ExtractionPayload(BaseModel):
    model_config = ConfigDict(frozen=True)

    ingredients: list[str]


class _MatchPayload(BaseModel):
    """매칭 구조화 출력 — 후보 원형(required 포함, 점수 없음). 점수는 scoring.py가 붙인다."""

    model_config = ConfigDict(frozen=True)

    suggestions: list[MatchCandidate]


_PayloadT = TypeVar("_PayloadT", bound=BaseModel)


def read_usage(
    meta: types.GenerateContentResponseUsageMetadata | None,
    model: str,
    price_input_per_m: float,
    price_output_per_m: float,
) -> LLMUsage:
    """호출 1건의 사용량 — 필드 구성은 T1 #6 실측 resolution. SDK 필드는 전부 Optional이라 0으로 정규화한다."""
    prompt_tokens = (meta.prompt_token_count if meta else None) or 0
    output_tokens = (meta.candidates_token_count if meta else None) or 0
    # thinking을 빠뜨리면 원가의 대부분이 증발한다 — T1 #6에서 3.5-flash는 78%였다.
    thought_tokens = (meta.thoughts_token_count if meta else None) or 0
    details = (meta.prompt_tokens_details if meta else None) or []
    image_tokens = sum(
        detail.token_count or 0
        for detail in details
        if detail.modality == types.MediaModality.IMAGE
    )
    return LLMUsage(
        prompt_tokens=prompt_tokens,
        output_tokens=output_tokens,
        thought_tokens=thought_tokens,
        image_tokens=image_tokens,
        # Gemini는 thinking을 output 단가로 과금한다(T1 #6).
        cost_usd=prompt_tokens * price_input_per_m / 1_000_000
        + (output_tokens + thought_tokens) * price_output_per_m / 1_000_000,
        model=model,
    )


class GeminiLLMService(BaseLLMService):
    """운영 구현 — google-genai 비동기 클라이언트. 프로세스 수명 동안 1개를 재사용한다."""

    def __init__(
        self,
        *,
        client: genai.Client,
        model: str,
        price_input_per_m: float,
        price_output_per_m: float,
    ) -> None:
        self._client = client
        self._model = model
        self._price_input_per_m = price_input_per_m
        self._price_output_per_m = price_output_per_m

    async def recognize(self, image_jpeg: bytes) -> RecognizeResponse:
        payload, usage = await self._generate(
            contents=[
                types.Part.from_bytes(data=image_jpeg, mime_type="image/jpeg"),
                prompts.RECOGNIZE_PROMPT,
            ],
            schema=_RecognitionPayload,
            timeout_ms=RECOGNIZE_TIMEOUT_MS,
        )
        return RecognizeResponse(
            ingredients=payload.ingredients,
            low_quality=payload.low_quality,
            usage=usage,
        )

    async def extract(self, title: str) -> ExtractResponse:
        payload, usage = await self._generate(
            contents=[prompts.extract_prompt(title)],
            schema=_ExtractionPayload,
            timeout_ms=EXTRACT_TIMEOUT_MS,
        )
        return ExtractResponse(ingredients=payload.ingredients, usage=usage)

    async def match(
        self, ingredients: Sequence[str], recipes: Sequence[MatchRecipe]
    ) -> MatchOutcome:
        payload, usage = await self._generate(
            contents=[prompts.match_prompt(ingredients, recipes)],
            schema=_MatchPayload,
            timeout_ms=MATCH_TIMEOUT_MS,
        )
        return MatchOutcome(candidates=payload.suggestions, usage=usage)

    async def _generate(
        self,
        *,
        contents: list[types.PartUnion],
        schema: type[_PayloadT],
        timeout_ms: int,
    ) -> tuple[_PayloadT, LLMUsage]:
        """구조화 출력 1회 — 실패 모양을 여기서 하나로 만든다. 어느 메서드에서 나든 라우터는 같은 걸 본다."""
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=contents,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=schema,
                    http_options=types.HttpOptions(timeout=timeout_ms),
                ),
            )
        except (errors.APIError, httpx.HTTPError) as exc:
            # 타임아웃·연결 오류는 SDK가 감싸지 않고 httpx 예외로 통과한다(실측 확인).
            raise UpstreamLLMError(f"업스트림 호출 실패: {type(exc).__name__}") from exc

        # response.text는 예외를 던지지 않는다 — 후보·본문이 없으면 None이다.
        text = response.text
        if not text:
            raise UpstreamLLMError("업스트림 응답에 본문이 없습니다")
        try:
            parsed = schema.model_validate_json(text)
        except ValidationError as exc:
            raise UpstreamLLMError("구조화 출력 파싱 실패") from exc
        usage = read_usage(
            response.usage_metadata,
            self._model,
            self._price_input_per_m,
            self._price_output_per_m,
        )
        return parsed, usage
