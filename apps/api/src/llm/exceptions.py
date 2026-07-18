# llm 도메인 예외 — 업스트림 실패를 한 모양으로 만든다. 어느 경로에서 나든 라우터는 같은 걸 본다.
class UpstreamLLMError(Exception):
    """Gemini 호출·응답 파싱의 모든 실패 — 라우터가 502로 번역한다."""


class IngestFetchError(Exception):
    """추출 사다리의 페이지 fetch 실패(네트워크·SSRF 차단·비HTML) — 다음 단으로 강등된다(#123).

    UpstreamLLMError와 달리 502가 되지 않는다 — 사다리의 결정적 단 실패는 제목 추론 폴백이다.
    """
