# #101 컨텍스트 노트 — 결정과 근거

작업 중 내린 결정을 시간순으로 기록한다. 플랜 정본은 `~/.claude/plans/101-structured-bird.md`.

## 2026-07-18 — 플래닝 (사용자 확정 4건)

- **점수 산식 = LLM required + 서버 순수 함수.** Gemini responseSchema에 제안별 `required`(필요 재료 전체) 배열을 추가로 받고, 서버가 `floor(100×(|required|−미해소 부족)/|required|)`를 계산한다. substitute가 있으면 해소로 간주(감점 없음). 근거 — ADR-0007("실 점수는 LLM 프록시가 반환")과 스펙 #96("매칭 % 산식은 순수 로직 유닛")을 동시에 만족하는 유일한 조합. LLM 직접 채점안은 비일관·검증 불가로 기각, substitute 0.5 감점안은 스펙 근거 없는 튜닝이라 기각.
- **wire 네이밍 = snake_case.** 루트 프록시는 "로직 이식 참조"일 뿐 계약 동등 대상이 아니다(티켓 명문). 이미 발행된 auth 계약(created_at)과 일관 유지가 우선. camelCase 패리티안 기각 — 발행 계약 안에서 모듈별 네이밍이 갈라지고 alias 보일러플레이트가 영구 잔존.
- **경로 = `/api/v1/llm/{recognize,extract,match}`.** auth 모듈(`/api/v1/auth/*`)과 동형인 도메인 프리픽스.
- **실 Gemini 스모크 전체 실행 승인.** 텍스트 2건 + 이미지 1건, 예상 < $0.002. 키는 루트 `.env.local`.

## 플래닝 중 확인된 사실 (구현 전제)

- google-genai 최신 2.12.x, py.typed 동봉 → mypy strict override 불필요. 타임아웃은 `HttpOptions(timeout=ms)` **밀리초**. usage_metadata 필드 전부 Optional → `or 0` 필수. 타임아웃·연결 오류는 httpx 예외로 그대로 통과 → `(errors.APIError, httpx.HTTPError)`를 잡는다.
- 구조화 출력은 Pydantic 클래스를 `response_schema`로 직접 전달 → `response.parsed`가 검증된 인스턴스. `parsed is None`은 예외가 아니라 정상 반환값이므로 직접 검사해 502로 만든다.
- schemathesis는 세션이 없어 3라우트 전부 401(문서화됨)로 끝난다 → CI에서 Gemini에 절대 도달하지 않는다. 세션 인증이 곧 CI의 비용 방어막.
- `.mjs` 프롬프트는 verbatim 이식하되 델타 2개만 허용(`# #101 이식 조정` 주석) — match에 required 규칙 1줄, recognize의 "lowQuality" 단어를 `low_quality`로.
- backend.md §4의 "Claude/anthropic" 명시는 ADR-0009 편차 ①에 따라 "프로바이더 교체 가능한 일반형"으로 읽는다 — 구조(집중·BaseLLMService·프롬프트 상수화)만 채택, 구현체는 google-genai.
