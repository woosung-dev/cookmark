# health 엔드포인트 + 실 DB 관통 통합 테스트 — 외부 행동(응답·DB 최종 상태)만 검증
import httpx
from sqlalchemy import text


async def test_health_returns_200(client: httpx.AsyncClient) -> None:
    res = await client.get("/api/v1/health")

    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


async def test_alembic_baseline_applied_to_real_db(migrated_db: str) -> None:
    """alembic upgrade head가 실 Postgres에 적용됐다 — alembic_version 행 존재 + SELECT 1."""
    from src.common.database import get_engine

    engine = get_engine()
    async with engine.connect() as conn:
        ping = await conn.execute(text("SELECT 1"))
        assert ping.scalar_one() == 1

        version = await conn.execute(text("SELECT version_num FROM alembic_version"))
        assert version.scalar_one()
