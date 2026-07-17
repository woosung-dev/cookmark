# 로컬→계정 이전 bulk 가져오기 입력 스키마 — 이미 추출된 재료를 그대로 수용한다 (티켓 #104)
#
# ⚠️ 시한부 모듈. 제거 트리거 = 파일럿 가구 2계정 이전 완료 (ADR-0009 데이터 이전 절). src/migration/ docstring 참조.
from pydantic import BaseModel, ConfigDict, Field


class RecipeImportItem(BaseModel):
    """로컬 레시피 북 항목 1개. ingredients는 로컬에서 이미 1회 추출됐으므로 그대로 보존한다 —
    서버가 재추출하지 않는다(재추출은 비용·결과 표류만 낳는다). 그래서 이 스키마엔 재료가 **있고**,
    저장 시 추출하는 recipes의 RecipeCreate엔 재료가 **없다**(비대칭은 의도).

    str_strip_whitespace를 켜지 않는다 — "보낸 그대로 보존"(AC)이라 재료 문자열을 손대지 않는다.
    """

    model_config = ConfigDict(extra="forbid")

    url: str = Field(min_length=1)
    title: str = Field(min_length=1)
    ingredients: list[str]


class RecipeImportRequest(BaseModel):
    """명시적 가져오기 1회의 페이로드. 빈 배치는 422 — 로컬에 레시피가 있을 때만 클라이언트가 부른다."""

    model_config = ConfigDict(extra="forbid")

    recipes: list[RecipeImportItem] = Field(min_length=1)
