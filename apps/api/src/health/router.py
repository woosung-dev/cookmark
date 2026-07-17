# health 라우터 — DB 미접촉 liveness. walking skeleton 로컬 절반의 첫 표면 (#97)
from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
