# llm 입출력 스키마 — Pydantic 모델이 계약의 정본이고 스냅샷은 생성물이다 (ADR-0009 계약 절)
from typing import Annotated, Literal

from pydantic import (
    Base64Bytes,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_validator,
)

# confidence 3단·라벨 의미는 ADR-0003과 한 몸이다 — 값을 바꾸면 클라이언트 초기 체크 상태가 깨진다.
Confidence = Literal["high", "medium", "low"]
SuggestionSource = Literal["saved", "generated"]

NonBlankStr = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


class LLMUsage(BaseModel):
    """호출 1건의 사용량 — 필드 구성은 T1 #6 실측 resolution. 토큰을 하나로 뭉치지 않는다."""

    model_config = ConfigDict(frozen=True)

    prompt_tokens: int
    output_tokens: int
    thought_tokens: int
    image_tokens: int
    cost_usd: float
    model: str


class RecognizeRequest(BaseModel):
    """인식 요청 — 클라이언트가 768px로 리사이즈한 JPEG의 base64. 디코드 실패·빈 이미지는 422다."""

    image_base64: Base64Bytes

    @field_validator("image_base64", mode="after")
    @classmethod
    def _reject_empty(cls, value: bytes) -> bytes:
        # Base64Bytes는 관대한 디코더라 비알파벳 문자열("!!!")이 빈 bytes로 통과한다 — 빈 이미지는 막는다.
        if not value:
            raise ValueError("image_base64가 비어 있다")
        return value


class RecognizedIngredient(BaseModel):
    model_config = ConfigDict(frozen=True)

    name: str
    confidence: Confidence


class RecognizeResponse(BaseModel):
    """인식 결과 — seam 반환 타입을 겸한다(후처리가 없어 wire 모델이 곧 경계 타입이다)."""

    model_config = ConfigDict(frozen=True)

    ingredients: list[RecognizedIngredient]
    low_quality: bool = False
    usage: LLMUsage


class ExtractRequest(BaseModel):
    """추출 요청 — 제목 + (있으면) 레시피 url. url이 있으면 서버가 URL 내용 기반 사다리를 탄다(#123)."""

    title: NonBlankStr
    url: str | None = None


class ExtractResponse(BaseModel):
    """추출 결과 — usage는 nullable(#123). JSON-LD 결정적 추출은 LLM을 안 돌아 usage가 없다."""

    model_config = ConfigDict(frozen=True)

    ingredients: list[str]
    usage: LLMUsage | None


class MatchRecipe(BaseModel):
    """매칭 입력의 저장 레시피 — 제목 + (있으면) 재료 목록. URL은 클라이언트에 남는다."""

    title: str
    ingredients: list[str] = Field(default_factory=list)


class MatchRequest(BaseModel):
    """매칭 요청 — ingredients는 체크·비뭉뚱그림만 온다(ADR-0002 필터는 클라이언트 소관)."""

    ingredients: list[str] = Field(min_length=1)
    recipes: list[MatchRecipe] = Field(default_factory=list)


class MissingIngredient(BaseModel):
    model_config = ConfigDict(frozen=True)

    name: str
    substitute: str | None = None


class Suggestion(BaseModel):
    """제안 1건 — match_score는 서버 산식 실산출이다(#101 신규, ADR-0007 이월 해소)."""

    model_config = ConfigDict(frozen=True)

    menu: str
    source: SuggestionSource
    missing: list[MissingIngredient]
    reason: str
    match_score: int = Field(ge=0, le=100)


class MatchResponse(BaseModel):
    """매칭 결과 — 후보 최대 6개를 그대로 낸다. 3개 상한·라벨 결정은 클라이언트 소관(무변경)."""

    model_config = ConfigDict(frozen=True)

    suggestions: list[Suggestion]
    usage: LLMUsage
