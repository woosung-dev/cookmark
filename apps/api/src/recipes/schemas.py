# recipes 입출력 스키마 — Pydantic 모델이 계약의 정본이고 OpenAPI 스냅샷은 생성물이다 (ADR-0009)
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class RecipeCreate(BaseModel):
    """ingredients는 받지 않는다 — 추출은 서버가 저장 시 1회 수행한다. 몰래 넣으면 422로 시끄럽게 거절."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    url: str = Field(min_length=1)
    title: str = Field(min_length=1)


class RecipeUpdate(BaseModel):
    """url은 불변 — 스키마에 없고 extra=forbid라 보내면 422다(조용한 무시가 아니라 계약). 재추출도 없다.

    null과 부재를 같게 본다(둘 다 무변경) — ingredients=[]는 null이 아니라 "비우기"다.
    """

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    title: str | None = Field(default=None, min_length=1)
    ingredients: list[str] | None = None


class RecipeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    url: str
    title: str
    ingredients: list[str]
    created_at: datetime
