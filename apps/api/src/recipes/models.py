# 레시피 테이블 — 출처 URL·사용자 제목·추출 재료만 남는다. 원본 저작물 무보관 (스펙 #96 글로서리)
import uuid
from datetime import UTC, datetime

from sqlalchemy import Column, DateTime, String
from sqlalchemy.dialects.postgresql import ARRAY
from sqlmodel import Field, SQLModel


def _now() -> datetime:
    # asyncpg는 timestamptz를 offset-aware로 돌려준다 — naive와 섞으면 비교에서 TypeError가 난다.
    return datetime.now(UTC)


class Recipe(SQLModel, table=True):
    """레시피 북 항목. Relationship()을 두지 않는 것은 의도다 — 관계를 걸면 계정 삭제 시
    SQLAlchemy가 owner_id를 NULL로 UPDATE하려다 NOT NULL을 위반한다. 파기는 DB의
    ON DELETE CASCADE에 맡긴다(§12.3, sessions 선례).
    """

    __tablename__ = "recipes"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    owner_id: uuid.UUID = Field(
        foreign_key="accounts.id", ondelete="CASCADE", index=True
    )
    url: str
    title: str
    # 항상 통째 교체(대입)만 한다 — in-place 변형이 없으므로 MutableList 추적이 필요 없다.
    # dialect ARRAY를 직접 쓴다 — reflect 결과와 동형이라 alembic check 왕복에 위양성이 없다.
    ingredients: list[str] = Field(sa_column=Column(ARRAY(String()), nullable=False))
    created_at: datetime = Field(
        default_factory=_now,
        sa_column=Column(DateTime(timezone=True), nullable=False),
    )
