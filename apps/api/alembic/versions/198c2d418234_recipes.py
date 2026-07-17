# Alembic 마이그레이션 — recipes (#103 서버 레시피 북)
"""recipes

레시피 = (id, owner_id, url, title, ingredients, created_at) — 원본 저작물 컬럼은 없다(글로서리).
owner FK는 ON DELETE CASCADE — 탈퇴 시 계정 삭제 하나로 레시피까지 파기된다(§12.3).

Revision ID: 198c2d418234
Revises: a8dc76751b1a
Create Date: 2026-07-18

"""

from collections.abc import Sequence

import sqlalchemy as sa
import sqlmodel  # SQLModel의 str 필드는 sqlmodel.sql.sqltypes.AutoString으로 렌더된다 — 없으면 NameError
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "198c2d418234"
down_revision: str | Sequence[str] | None = "a8dc76751b1a"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "recipes",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("url", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("title", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("ingredients", postgresql.ARRAY(sa.String()), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["owner_id"], ["accounts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_recipes_owner_id"), "recipes", ["owner_id"], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f("ix_recipes_owner_id"), table_name="recipes")
    op.drop_table("recipes")
