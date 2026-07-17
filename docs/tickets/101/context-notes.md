# #101 컨텍스트 노트 — 결정과 근거

작업 중 내린 결정을 시간순으로 기록한다. 플랜 정본은 `~/.claude/plans/101-structured-bird.md`.

## 2026-07-18 — 플래닝 (사용자 확정 4건)

- **점수 산식 = LLM required + 서버 순수 함수.** Gemini responseSchema에 제안별 `required`(필요 재료 전체) 배열을 추가로 받고, 서버가 `floor(100×(|required|−미해소 부족)/|required|)`를 계산한다. substitute가 있으면 해소로 간주(감점 없음). 근거 — ADR-0007("실 점수는 LLM 프록시가 반환")과 스펙 #96("매칭 % 산식은 순수 로직 유닛")을 동시에 만족하는 유일한 조합. LLM 직접 채점안은 비일관·검증 불가로 기각, substitute 0.5 감점안은 스펙 근거 없는 튜닝이라 기각.
- **wire 네이밍 = snake_case.** 루트 프록시는 "로직 이식 참조"일 뿐 계약 동등 대상이 아니다(티켓 명문). 이미 발행된 auth 계약(created_at)과 일관 유지가 우선. camelCase 패리티안 기각 — 발행 계약 안에서 모듈별 네이밍이 갈라지고 alias 보일러플레이트가 영구 잔존.
- **경로 = `/api/v1/llm/{recognize,extract,match}`.** auth 모듈(`/api/v1/auth/*`)과 동형인 도메인 프리픽스.
- **실 Gemini 스모크 전체 실행 승인.** 텍스트 2건 + 이미지 1건, 예상 < $0.002. 키는 루트 `.env.local`.

## 플래닝 중 확인된 사실 (구현 전제)

- google-genai 최신 2.12.x, py.typed 동봉 → mypy strict override 불필요. 타임아웃은 `HttpOptions(timeout=ms)` **밀리초**. usage_metadata 필드 전부 Optional → `or 0` 필수. 타임아웃·연결 오류는 httpx 예외로 그대로 통과 → `(errors.APIError, httpx.HTTPError)`를 잡는다.
- 구조화 출력은 Pydantic 클래스를 `response_schema`로 직접 전달한다. 구현은 `response.parsed` 대신 `response.text` + `model_validate_json` 단일 경로를 택했다 — SDK는 검증 실패를 예외 없이 `parsed=None`으로 삼키므로, 직접 검증이 실패 모양을 하나로 만들고 `.mjs`(text→parse) 이식에도 정확히 대응한다.
- schemathesis는 세션이 없어 3라우트 전부 401(문서화됨)로 끝난다 → CI에서 Gemini에 절대 도달하지 않는다. 세션 인증이 곧 CI의 비용 방어막.
- `.mjs` 프롬프트는 verbatim 이식하되 델타 2개만 허용(`# #101 이식 조정` 주석) — match에 required 규칙 1줄, recognize의 "lowQuality" 단어를 `low_quality`로.
- backend.md §4의 "Claude/anthropic" 명시는 ADR-0009 편차 ①에 따라 "프로바이더 교체 가능한 일반형"으로 읽는다 — 구조(집중·BaseLLMService·프롬프트 상수화)만 채택, 구현체는 google-genai.

## 2026-07-18 — 구현 중 발견

- **Pydantic `Base64Bytes`는 관대한 디코더다** — 비알파벳 문자열("!!!")이 오류 없이 빈 bytes로 통과한다. `Field(min_length=1)`은 이를 못 막아(인코딩 문자열 쪽에 걸림) after-validator로 빈 이미지를 422 처리했다. 유효 문자로 된 쓰레기 base64는 통과해 Gemini 400→우리 502로 흐른다 — `.mjs`(무검증)와 동일 거동이라 수용.
- **로컬 schemathesis 재현이 미문서 400을 잡았다** — UTF-8 디코드 불가 본문에 FastAPI가 `400 {"detail":"There was an error parsing the body"}`를 낸다(422 아님). auth 라우트는 전부 GET이라 이제껏 안 보였다. 3라우트 `responses`에 400을 문서화하고 스냅샷 재생성 → 546 케이스 전부 통과.
- **CI의 비용 방어막 = 세션 인증** — schemathesis는 세션 없이 fuzzing하므로 3라우트 전부 401(문서화됨)에서 끝난다. `GEMINI_API_KEY: placeholder`가 실제로 쓰일 일이 없다.

## 2026-07-18 — 실 Gemini 스모크 (AC 7, 총 $0.00146)

- 추출("김치찌개") → 재료 9개, $0.00010. 매칭(재료 4 + 저장 레시피 1) → 후보 5개(≤6 준수), saved 우선, `match_score` 80/60/100/75/60 — required 기반 산식이 실데이터에서 결정적으로 동작. 인식(합성 768px 이미지) → `low_quality=true`·빈 목록(프롬프트의 판독불가 규칙 그대로), **`image_tokens=1064` 고정 불변식 재현**, 모델 `gemini-3.1-flash-lite` 확인.
- **`required` 필드의 원가 영향(정직 기록)** — 매칭 출력 토큰 225→643으로 늘어 매칭 1건 ≈$0.0004→$0.0011. 루프(인식+매칭) ≈$0.0018로 승계 기준 $0.0011 대비 증가. 파일럿 원가 판정(T1 #6)에는 무해한 자릿수지만, 원가에 민감해지면 required를 개수 필드로 줄이는 선택지가 있다.
- 스모크 이미지는 개인 사진 대신 로컬 합성 이미지(순수 Python PNG→sips JPEG)를 썼다 — 외부 API로 개인 데이터를 보내지 않기 위함.
- 구조화 출력의 `str | None`(substitute)·`required` 배열 모두 SDK Pydantic→Schema 변환을 실데이터로 통과 확인.
