# 계정·세션 테이블 — 계정은 (내부 id, iss, sub, created_at)이 전부다 (backend.md §12.1 최소 식별자)
import uuid
from datetime import UTC, datetime

from sqlalchemy import Column, DateTime, UniqueConstraint
from sqlmodel import Field, SQLModel


def _now() -> datetime:
    # asyncpg는 timestamptz를 offset-aware로 돌려준다 — naive와 섞으면 만료 비교에서 TypeError가 난다.
    return datetime.now(UTC)


class Account(SQLModel, table=True):
    """소셜 연합 계정. 이메일·닉네임·프로필사진은 수집하지 않는다 — 용처가 0이면 자산이 아니라 부채다(§12.1)."""

    __tablename__ = "accounts"
    # 재로그인 시 계정이 갈리지 않는 것을 관례가 아니라 DB 제약으로 보장한다.
    __table_args__ = (UniqueConstraint("iss", "sub", name="uq_accounts_iss_sub"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    iss: str
    sub: str
    created_at: datetime = Field(
        default_factory=_now,
        sa_column=Column(DateTime(timezone=True), nullable=False),
    )


class AuthSession(SQLModel, table=True):
    """앱 소유 세션. 불투명 토큰의 해시만 남는다 — 원문은 클라이언트에만 산다.

    Relationship()을 두지 않는 것은 의도다 — 관계를 걸면 계정 삭제 시 SQLAlchemy가 account_id를
    NULL로 UPDATE하려다 NOT NULL을 위반한다. 파기는 DB의 ON DELETE CASCADE에 맡긴다(§12.3).
    """

    __tablename__ = "sessions"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    token_hash: str = Field(unique=True, index=True)
    account_id: uuid.UUID = Field(
        foreign_key="accounts.id", ondelete="CASCADE", index=True
    )
    created_at: datetime = Field(
        default_factory=_now,
        sa_column=Column(DateTime(timezone=True), nullable=False),
    )
    expires_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), nullable=False)
    )
