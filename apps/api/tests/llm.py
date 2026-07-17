# 테스트용 결정적 LLM 페이크 — dependency_overrides로 get_llm_service 자리에 주입된다 (스펙 #96 seam)
from collections.abc import Sequence

from src.llm.exceptions import UpstreamLLMError
from src.llm.schemas import (
    ExtractResponse,
    LLMUsage,
    MatchRecipe,
    MissingIngredient,
    RecognizedIngredient,
    RecognizeResponse,
)
from src.llm.service import BaseLLMService, MatchCandidate, MatchOutcome

# 픽스처는 apps/mobile fake_llm_gateway.dart의 정본 데이터를 미러한다 — confidence 3단 혼합 + 뭉뚱그림 1개.
RECOGNITION_FIXTURE = [
    RecognizedIngredient(name="대파", confidence="high"),
    RecognizedIngredient(name="계란", confidence="high"),
    RecognizedIngredient(name="두부", confidence="high"),
    RecognizedIngredient(name="애호박", confidence="medium"),
    RecognizedIngredient(name="반찬통", confidence="medium"),
    RecognizedIngredient(name="고추장", confidence="low"),
    RecognizedIngredient(name="표고버섯", confidence="low"),
]

# usage 수치는 T1 #6 실측(인식 1157/295/1064 → $0.00073, 텍스트 395/225 → $0.00044)을 그대로 쓴다.
RECOGNITION_USAGE = LLMUsage(
    prompt_tokens=1157,
    output_tokens=295,
    thought_tokens=0,
    image_tokens=1064,
    cost_usd=0.00073,
    model="fake-recognizer",
)
TEXT_USAGE = LLMUsage(
    prompt_tokens=395,
    output_tokens=225,
    thought_tokens=0,
    image_tokens=0,
    cost_usd=0.00044,
    model="fake-matcher",
)

EXTRACTIONS = {
    "김치찌개": ["김치", "돼지고기", "두부", "대파", "고춧가루"],
    "애호박볶음": ["애호박", "대파", "소금", "식용유"],
    "계란찜": ["계란", "대파", "새우젓"],
    # 요리명 미인식 → 빈 배열은 프롬프트가 정의한 정상 출력이다(실패 아님) — recipes 저장 경로가 쓴다(#103).
    "ㅁㄴㅇㄹ": [],
}
FALLBACK_EXTRACTION = ["소금", "식용유"]

DEFAULT_REQUIRED = ["김치", "돼지고기", "두부", "대파", "고춧가루"]


class FakeLLMService(BaseLLMService):
    """결정적 페이크 — 호출 인자를 기록하고 고정 픽스처를 돌려준다. failure를 켜면 전 경로가 502다."""

    def __init__(self) -> None:
        self.failure: UpstreamLLMError | None = None
        self.recognized_images: list[bytes] = []
        self.extracted_titles: list[str] = []
        self.match_calls: list[tuple[list[str], list[MatchRecipe]]] = []

    async def recognize(self, image_jpeg: bytes) -> RecognizeResponse:
        if self.failure is not None:
            raise self.failure
        self.recognized_images.append(image_jpeg)
        return RecognizeResponse(
            ingredients=RECOGNITION_FIXTURE, low_quality=False, usage=RECOGNITION_USAGE
        )

    async def extract(self, title: str) -> ExtractResponse:
        if self.failure is not None:
            raise self.failure
        self.extracted_titles.append(title)
        return ExtractResponse(
            ingredients=EXTRACTIONS.get(title, FALLBACK_EXTRACTION), usage=TEXT_USAGE
        )

    async def match(
        self, ingredients: Sequence[str], recipes: Sequence[MatchRecipe]
    ) -> MatchOutcome:
        if self.failure is not None:
            raise self.failure
        self.match_calls.append((list(ingredients), list(recipes)))
        candidates: list[MatchCandidate] = []
        if recipes:
            candidates.append(
                MatchCandidate(
                    menu=recipes[0].title,
                    source="saved",
                    missing=[],
                    reason="냉장고에 있는 재료로 다 돼요.",
                    required=list(recipes[0].ingredients) or DEFAULT_REQUIRED,
                )
            )
        candidates.extend(
            [
                # 산식 75점 — 필요 4 중 미해소 1.
                MatchCandidate(
                    menu="애호박볶음",
                    source="generated",
                    missing=[MissingIngredient(name="식용유")],
                    reason="애호박이 있어서 금방 만들 수 있어요.",
                    required=["애호박", "대파", "소금", "식용유"],
                ),
                # 산식 100점 — 부족이 substitute로 전부 해소.
                MatchCandidate(
                    menu="두부조림",
                    source="generated",
                    missing=[MissingIngredient(name="우유", substitute="두유")],
                    reason="두부가 있고 우유는 두유로 대신할 수 있어요.",
                    required=["두부", "우유", "간장", "설탕"],
                ),
            ]
        )
        return MatchOutcome(candidates=candidates, usage=TEXT_USAGE)
