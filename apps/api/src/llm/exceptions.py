# llm 도메인 예외 — 업스트림 실패를 한 모양으로 만든다. 어느 경로에서 나든 라우터는 같은 걸 본다.
class UpstreamLLMError(Exception):
    """Gemini 호출·응답 파싱의 모든 실패 — 라우터가 502로 번역한다."""
