# 테스트용 결정적 LLM 페이크 — 스펙 #96 seam ①. seam ②(respx)와 달리 dependency override로 주입한다.
from src.services.ai_processing import BaseLLMService, ExtractionUnavailable


class FakeLLMService(BaseLLMService):
    """설정 가능한 결정적 페이크 — result를 돌려주거나, fail() 이후에는 ExtractionUnavailable을 던진다."""

    def __init__(self) -> None:
        self.result: list[str] = ["계란", "대파"]
        self.error: ExtractionUnavailable | None = None
        # 호출 인자 관찰 — PATCH가 재추출하지 않음을 증명할 때 쓴다.
        self.calls: list[str] = []

    def fail(self, message: str = "추출 업스트림 불능") -> None:
        self.error = ExtractionUnavailable(message)

    async def extract_ingredients(self, title: str) -> list[str]:
        self.calls.append(title)
        if self.error is not None:
            raise self.error
        return list(self.result)
