# og:image 라우터 — HTTP 전용. fetch·SSRF 판정은 service·guard에 위임한다 (backend.md §3)
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import HttpUrl

from src.auth.dependencies import UNAUTHORIZED, CurrentAccount
from src.ogimage import service
from src.ogimage.exceptions import OgImageBlocked
from src.ogimage.schemas import OgImageResponse

router = APIRouter(prefix="/og-image", tags=["og-image"])

BLOCKED: dict[int | str, dict[str, str]] = {
    400: {"description": "허용되지 않는 대상 주소"}
}


@router.get("", responses={**UNAUTHORIZED, **BLOCKED})
async def read_og_image(
    url: Annotated[HttpUrl, Query(description="레시피 출처 페이지 URL")],
    account: CurrentAccount,
) -> OgImageResponse:
    """출처 페이지의 og:image URL — 제안 카드 음식 사진용. 부재는 명시적 null이다."""
    try:
        image_url = await service.fetch_og_image(str(url))
    except OgImageBlocked as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="허용되지 않는 대상 주소"
        ) from exc
    return OgImageResponse(image_url=image_url)
