# 빈 베이스라인 — upgrade head 파이프라인 증명용. 실제 스키마는 후속 티켓(#100·#103)이 쌓는다.
"""baseline

Revision ID: 6b8076167b5b
Revises:
Create Date: 2026-07-17
"""

from collections.abc import Sequence

# revision identifiers, used by Alembic.
revision: str = "6b8076167b5b"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
