# llm 라우터 — HTTP 전용. LLM 호출은 seam(service) 뒤로, 점수 조립은 scoring으로 위임한다 (backend.md §3)
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from src.auth.dependencies import CurrentAccount
from src.llm.dependencies import get_llm_service
from src.llm.exceptions import UpstreamLLMError
from src.llm.schemas import (
    ExtractRequest,
    ExtractResponse,
    MatchRequest,
    MatchResponse,
    RecognizeRequest,
    RecognizeResponse,
)
from src.llm.scoring import build_match_response
from src.llm.service import BaseLLMService

router = APIRouter(prefix="/llm", tags=["llm"])

Service = Annotated[BaseLLMService, Depends(get_llm_service)]

# 401·502는 이 라우트들이 실제로 내는 응답이다 — 문서화해야 생성된 계약이 구현과 어긋나지 않는다(#99).
# 세 라우트 전부 세션 필수(무세션 401)라 공개 URL의 LLM 비용 표면이 닫히고,
# schemathesis fuzzing도 전부 401에서 끝나 CI가 Gemini에 도달할 일이 없다.
RESPONSES: dict[int | str, dict[str, str]] = {
    # 400은 FastAPI가 UTF-8/JSON 디코드 불가 본문에 내는 응답이다 — 실 서버 fuzzing이 실제로 관측했다.
    400: {"description": "본문 파싱 실패"},
    401: {"description": "세션이 없거나 유효하지 않다"},
    502: {"description": "LLM 업스트림 호출 실패"},
}


def _bad_gateway(exc: UpstreamLLMError) -> HTTPException:
    return HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))


@router.post("/recognize", responses=RESPONSES)
async def recognize(
    account: CurrentAccount, body: RecognizeRequest, service: Service
) -> RecognizeResponse:
    """냉장고 사진에서 재료 후보를 얻는다. 이미지는 메모리로만 지나간다 — 저장·로깅 없음(스펙 #96)."""
    try:
        return await service.recognize(body.image_base64)
    except UpstreamLLMError as exc:
        raise _bad_gateway(exc) from exc


@router.post("/extract", responses=RESPONSES)
async def extract(
    account: CurrentAccount, body: ExtractRequest, service: Service
) -> ExtractResponse:
    """레시피 제목에서 재료를 추론한다 — 제목만 본다(본문·자막 금지)."""
    try:
        return await service.extract(body.title)
    except UpstreamLLMError as exc:
        raise _bad_gateway(exc) from exc


@router.post("/match", responses=RESPONSES)
async def match(
    account: CurrentAccount, body: MatchRequest, service: Service
) -> MatchResponse:
    """확정 재료 + 저장 레시피로 후보를 받고 매치 점수를 실산출해 낸다(#101 이월 해소)."""
    try:
        outcome = await service.match(body.ingredients, body.recipes)
    except UpstreamLLMError as exc:
        raise _bad_gateway(exc) from exc
    return build_match_response(outcome)
