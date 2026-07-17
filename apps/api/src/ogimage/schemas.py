# og:image 응답 스키마 — 부재를 명시적 null로 나른다 (#102 AC: 부재 응답, 500 아님)
from pydantic import BaseModel


class OgImageResponse(BaseModel):
    # str이지 HttpUrl이 아니다 — 이상한 upstream 값이 응답 검증 500으로 튀지 않게
    image_url: str | None
