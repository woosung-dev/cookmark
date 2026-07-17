# recipes 라우터 — HTTP 전용. 도메인 예외를 상태 코드로 옮기는 것까지만 한다 (backend.md §3)
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from src.recipes.dependencies import get_recipe_book_service
from src.recipes.exceptions import RecipeNotFound
from src.recipes.schemas import RecipeCreate, RecipeResponse, RecipeUpdate
from src.recipes.service import RecipeBookService
from src.services.ai_processing import ExtractionUnavailable

router = APIRouter(prefix="/recipes", tags=["recipes"])

Service = Annotated[RecipeBookService, Depends(get_recipe_book_service)]

# 계약 가드(#99)가 실 서버로 검증한다 — 라우트가 실제로 내는 코드는 전부 문서화한다 (auth/router.py 동형).
UNAUTHORIZED: dict[int | str, dict[str, str]] = {
    401: {"description": "세션이 없거나 유효하지 않다"}
}
# 부재와 남의 것이 바이트 동일 응답이어야 한다 — 존재를 노출하지 않는다 (§12.2, 403 아님).
NOT_FOUND: dict[int | str, dict[str, str]] = {
    404: {"description": "레시피를 찾을 수 없다"}
}
EXTRACTION_FAILED: dict[int | str, dict[str, str]] = {
    502: {"description": "재료 추출에 실패했다 — 레시피는 저장되지 않았다"}
}

_NOT_FOUND_DETAIL = "레시피를 찾을 수 없다"


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    responses={**UNAUTHORIZED, **EXTRACTION_FAILED},
)
async def create_recipe(payload: RecipeCreate, service: Service) -> RecipeResponse:
    """저장하면 제목에서 재료 추출이 1회 일어나 항목에 남는다. 추출 실패는 명시적 502 — 조용한 저장 없음."""
    try:
        recipe = await service.create(url=payload.url, title=payload.title)
    except ExtractionUnavailable as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="재료 추출에 실패해 저장하지 않았다",
        ) from exc
    return RecipeResponse.model_validate(recipe)


@router.get("", responses=UNAUTHORIZED)
async def list_recipes(service: Service) -> list[RecipeResponse]:
    """소유자 항목만, 삽입순(created_at·id) — 스코프는 Repository 생성 시점에 이미 끝났다."""
    return [RecipeResponse.model_validate(r) for r in await service.list()]


@router.get("/{recipe_id}", responses={**UNAUTHORIZED, **NOT_FOUND})
async def read_recipe(recipe_id: UUID, service: Service) -> RecipeResponse:
    try:
        return RecipeResponse.model_validate(await service.get(recipe_id))
    except RecipeNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=_NOT_FOUND_DETAIL
        ) from exc


@router.patch("/{recipe_id}", responses={**UNAUTHORIZED, **NOT_FOUND})
async def update_recipe(
    recipe_id: UUID, payload: RecipeUpdate, service: Service
) -> RecipeResponse:
    """url은 불변이고 재추출은 없다 — 바꿀 수 있는 건 title·ingredients뿐이다."""
    try:
        recipe = await service.update(
            recipe_id, title=payload.title, ingredients=payload.ingredients
        )
    except RecipeNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=_NOT_FOUND_DETAIL
        ) from exc
    return RecipeResponse.model_validate(recipe)


@router.delete(
    "/{recipe_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={**UNAUTHORIZED, **NOT_FOUND},
)
async def delete_recipe(recipe_id: UUID, service: Service) -> None:
    try:
        await service.delete(recipe_id)
    except RecipeNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=_NOT_FOUND_DETAIL
        ) from exc
