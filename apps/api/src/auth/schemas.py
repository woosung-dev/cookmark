# auth 입출력 스키마 — Pydantic 모델이 계약의 정본이고 OpenAPI 스냅샷은 생성물이다 (ADR-0009 계약 절)
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class AccountResponse(BaseModel):
    """서버가 계정에 대해 아는 전부. 더 있는 것처럼 보이지 않게 이게 그대로 계약이다."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    iss: str
    sub: str
    created_at: datetime


class SessionResponse(BaseModel):
    """발급된 세션. 웹은 쿠키로 받으므로 token을 무시하고, 네이티브는 이 값을 보안 저장소에 넣는다 (§9)."""

    token: str
    expires_at: datetime
    account: AccountResponse
