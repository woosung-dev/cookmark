# LLM 호출 집중 모듈 — BaseLLMService seam. 라우트·도메인은 google-genai를 직접 부르지 않는다 (backend.md §4)
from abc import ABC, abstractmethod
from functools import lru_cache

import httpx
from google import genai
from google.genai import errors, types
from pydantic import BaseModel

from src.common.prompts import INGREDIENT_EXTRACTION_PROMPT
from src.core.config import get_settings

# 승계 프록시와 동일 (api/extract.mjs UPSTREAM_TIMEOUT_MS — 텍스트 온리라 인식보다 빠르다)
EXTRACTION_TIMEOUT_MS = 15_000


class ExtractionUnavailable(Exception):
    """재료 추출이 완료되지 못했다 — 업스트림 오류·타임아웃·비정형 응답 전부 여기로 모인다.

    빈 목록은 여기 속하지 않는다 — 요리명 미인식 시 []는 프롬프트가 정의한 정상 출력이다.
    """


class _IngredientExtraction(BaseModel):
    """Gemini 구조화 출력 스키마 — 승계 프록시(api/extract.mjs)의 RESPONSE_SCHEMA와 동형."""

    ingredients: list[str]


class BaseLLMService(ABC):
    """LLM에 대한 페이크 주입 지점은 이 인터페이스 하나뿐이다 (스펙 #96 seam ①).

    #101(인식·매칭 승계)이 이 인터페이스에 메서드를 추가한다 — 여기 있는 건 #103 몫뿐이다.
    """

    @abstractmethod
    async def extract_ingredients(self, title: str) -> list[str]:
        """제목만 보고 통상 재료를 추론한다. 실패는 ExtractionUnavailable로 — None·부분 성공 없음."""


class GeminiLLMService(BaseLLMService):
    def __init__(self, client: genai.Client, model: str) -> None:
        self._client = client
        self._model = model

    async def extract_ingredients(self, title: str) -> list[str]:
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=INGREDIENT_EXTRACTION_PROMPT.format(title=title),
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=_IngredientExtraction,
                    http_options=types.HttpOptions(timeout=EXTRACTION_TIMEOUT_MS),
                ),
            )
        except (errors.APIError, httpx.HTTPError) as exc:
            # APIError = 업스트림 4xx/5xx. 타임아웃·전송 실패는 SDK가 안 감싸고 httpx로 새어 나온다.
            raise ExtractionUnavailable(str(exc)) from exc

        parsed = response.parsed
        if not isinstance(parsed, _IngredientExtraction):
            # SDK는 파싱·검증 실패를 조용히 None으로 눕힌다 — 조용한 실패를 명시적 에러로 승격한다.
            raise ExtractionUnavailable("구조화 출력을 파싱하지 못했다")
        return parsed.ingredients


@lru_cache
def get_llm_service() -> BaseLLMService:
    """지연 생성 — 설정이 갖춰진 뒤에 API 키를 읽는다 (get_oauth·get_engine 동형).

    테스트의 페이크 주입은 app.dependency_overrides[get_llm_service] 한 곳이다 (스펙 #96 seam ①).
    """
    settings = get_settings()
    client = genai.Client(api_key=settings.gemini_api_key.get_secret_value())
    return GeminiLLMService(client, settings.gemini_model)
