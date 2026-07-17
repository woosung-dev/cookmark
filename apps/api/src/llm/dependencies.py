# Depends() 조립 — 페이크 주입(dependency_overrides)의 유일한 표적이다 (backend.md §3 · 스펙 #96 seam)
from functools import lru_cache

from google import genai

from src.core.config import get_settings
from src.llm.gemini import GeminiLLMService
from src.llm.service import BaseLLMService


@lru_cache
def get_gemini_service() -> GeminiLLMService:
    """지연 1회 생성 — 설정이 갖춰진 뒤에 키를 읽고, 클라이언트는 프로세스 수명 동안 재사용한다 (oidc.get_oauth 동형)."""
    settings = get_settings()
    return GeminiLLMService(
        client=genai.Client(api_key=settings.gemini_api_key.get_secret_value()),
        model=settings.gemini_model,
        price_input_per_m=settings.gemini_price_input_per_m,
        price_output_per_m=settings.gemini_price_output_per_m,
    )


def get_llm_service() -> BaseLLMService:
    """LLM seam 획득 — 테스트는 app.dependency_overrides로 이 함수를 페이크로 바꾼다."""
    return get_gemini_service()
