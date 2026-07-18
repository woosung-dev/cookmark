# 이전 라우터 — HTTP 전용. POST /migration/recipes (bulk 가져오기 1회). 도메인 예외를 상태 코드로 옮긴다 (backend.md §3)
#
# ⚠️ 시한부 모듈. 제거 트리거는 src/migration/ __init__.py 참조.
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from src.auth.dependencies import UNAUTHORIZED
from src.migration.dependencies import get_recipe_import_service
from src.migration.exceptions import RecipeImportFailed
from src.migration.schemas import RecipeImportRequest
from src.migration.service import RecipeImportService
from src.recipes.schemas import RecipeResponse

# 전용 /migration 네임스페이스 — recipes와 경로가 겹치지 않게 한다. /recipes/import는 /recipes/{recipe_id}와
# 충돌한다: 정의 안 된 메서드(PATCH 등)가 {recipe_id} 라우트로 흘러 405 대신 422를 내 schemathesis
# "Unsupported methods" 검사가 실패한다(CI 실측). 별도 네임스페이스라 제거 시 그룹·경로째 사라진다.
router = APIRouter(prefix="/migration", tags=["migration"])

Service = Annotated[RecipeImportService, Depends(get_recipe_import_service)]

# FastAPI는 본문 JSON 디코드를 의존성 해석보다 먼저 한다 — 깨진 본문은 401보다 먼저 400이다(#103 실측).
BAD_REQUEST: dict[int | str, dict[str, str]] = {
    400: {"description": "본문을 파싱할 수 없다(JSON 디코드 실패)"}
}
# 원자적 등록이 실패하면 전량 롤백돼 아무것도 저장되지 않는다 — 클라이언트는 이 코드를 보고 로컬을 유지한다.
IMPORT_FAILED: dict[int | str, dict[str, str]] = {
    500: {
        "description": "가져오기에 실패했다 — 아무것도 저장되지 않았다(로컬 데이터 유지)"
    }
}


@router.post(
    "/recipes",
    status_code=status.HTTP_201_CREATED,
    responses={**BAD_REQUEST, **UNAUTHORIZED, **IMPORT_FAILED},
)
async def import_recipes(
    payload: RecipeImportRequest, service: Service
) -> list[RecipeResponse]:
    """로컬 레시피 북 전체를 계정에 1회 올린다 — 재추출 없이 재료를 그대로 수용하고, 전량 성공 또는 전량 실패다.

    성공(201)이면 클라이언트가 로컬을 지운다. 실패(500)면 아무것도 저장되지 않았으니 로컬을 유지한다.
    """
    try:
        saved = await service.import_all(payload.recipes)
    except RecipeImportFailed as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="가져오기에 실패해 아무것도 저장하지 않았다",
        ) from exc
    return [RecipeResponse.model_validate(recipe) for recipe in saved]
