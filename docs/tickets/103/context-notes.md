# #103 컨텍스트 노트 — 결정과 근거

다음 세션(사람·에이전트)이 재도출 없이 이어받기 위한 기록. AC·설계 원문은 이슈 #103과 스펙 #96.

## 조율 결정

- **#101 blocked-by를 사용자 승인으로 해제하고 #103이 seam을 선점했다** (2026-07-18 사용자 결정). `BaseLLMService`는 의도적으로 `extract_ingredients` 하나만 가진다 — #101이 recognize·match를 같은 인터페이스·같은 파일에 append한다. 늦게 머지되는 쪽이 조정한다(선례: exp2b-r2 자율조정). usage/원가 산식(`_gemini.mjs readUsage`)은 **이식하지 않았다** — 프록시 승계 응답 패리티가 필요한 #101의 몫이다.
- **충돌 최소화 배치** — conftest·main.py·config·api.yml·export_openapi는 전부 append-only 1~2줄. `contracts/openapi.yaml`은 충돌 시 손머지 말고 재생성. uv.lock은 `checkout --theirs` 후 `uv lock` 재생성(머지 교훈 메모).

## 설계 결정 (코드에 안 보이는 이유들)

- **추출 실패 vs 빈 배열** — `ExtractionUnavailable` → 502 + 미저장(AC5). 그러나 성공-빈배열은 **201 저장**이다: 프롬프트가 "요리명 미인식 시 빈 배열"을 정당 출력으로 정의한다(extract.mjs 승계). 모바일 #34의 "실패를 []로 눕히는 조용한 저장"과 다른 것은 실패의 **경로**다 — 에러는 절대 []로 변환되지 않는다.
- **PATCH = `{title?, ingredients?}`, url 불변, 재추출 없음** — 글로서리 "추출은 저장 시 1회". 재료 수정은 사용자 직접(모바일도 재추출 재시도·수동 관리 패턴). url은 모바일에서 곧 식별자·백업 병합 dedup 키라 불변. `extra="forbid"`로 url 전송은 422(조용한 무시 금지).
- **목록 삽입순(created_at ASC, id)** — 모바일 레시피 북 표시 순서(append)·#104 bulk import 순서 보존과 패리티. 최신순이 필요해지면 클라이언트 소비 접점(#38 후)에서 재론.
- **unique(owner_id, url) 미채택** — 중복 URL 정책은 bulk 가져오기 dedup을 설계할 #104의 몫. 지금 넣으면 409 표면이 계약에 선지불된다.
- **ingredients = `postgresql.ARRAY(String)`** (JSONB 기각) — 원소 타입 DB 강제·asyncpg 네이티브 바인딩·alembic check 왕복 동형(dialect 타입을 모델에 직접 써서 reflect와 같은 모양). 항상 통째 대입이라 MutableList 불요.
- **`RecipeNotFound` 하나로 부재·타인 소유 동일 처리** — 404 응답이 바이트 동일해야 존재가 새지 않는다(§12.2). 테스트가 진짜 부재 404와 json 비교로 고정.
- **`list` 메서드는 클래스 본문 마지막** — 앞 메서드의 `list[...]` annotation이 builtin 대신 방금 정의된 메서드를 잡아 import 시 `TypeError: 'function' object is not subscriptable`(Python 3.13, annotation 즉시 평가). mypy·ruff 둘 다 못 잡고 수집 단계에서 전 테스트가 죽는 함정.
- **마이그레이션 손작성** — autogenerate는 로컬 DB 연결이 필요하고, 정합은 어차피 `test_migrations`(실 컨테이너 `alembic check`)가 증명한다. `import sqlmodel`(AutoString NameError 방지)·FK `ondelete="CASCADE"` 존재를 손으로 보증.

## 함정 실측 (재현하면 여기부터)

- google-genai 2.12.1: `HttpOptions(timeout=…)`은 **밀리초**, `response.parsed`는 `BaseModel|dict|Enum|None`(isinstance 내로잉 필수 — SDK는 파싱 실패를 조용히 None으로 눕힘), 타임아웃·전송 예외는 SDK가 안 감싸고 httpx로 샌다, py.typed 동봉(mypy override 불요).
- 테스트의 실 네트워크 유출 방지 — recipes 테스트 파일마다 module autouse `_llm_guard(llm)`. override 누락 시 가짜 키로 실 Gemini 호출(15s 후 502)이라 느리게 빨갛다.
- 두 계정 분리는 Bearer 헤더 — `idp.login` 후 `client.cookies.clear()`, 헤더가 쿠키를 이긴다(기존 `test_me_with_bearer` 검증 사실).
- schemathesis는 무인증 fuzz — 신규 라우트는 401 문서화만 하면 통과, LLM 호출 0회(CurrentAccount가 본문 **검증**(422) 전 401). 신규 exclude 불요.
- **본문 라우트의 숨은 400** — FastAPI는 본문 JSON **디코드**를 의존성 해석보다 먼저 한다. 깨진 본문(`-d '\x80'`)은 401이 아니라 400 "There was an error parsing the body"다 — 본문 받는 라우트(POST·PATCH)는 400 문서화 필수. #99·#100에서 안 발현된 이유 = 본문 받는 라우트가 이번이 처음. schemathesis가 CI에서 실측으로 잡았고(`test_malformed_body_is_400_even_before_auth`로 핀), #101 프록시 라우트도 전부 본문을 받으므로 **같은 400 문서화가 필요하다**.

## 파운더 이월 (이 티켓 밖)

- 첫 실 배포 전 `cookmark-gemini-api-key` 프로비저닝 + deploy `--set-secrets`·마이그레이션 env 확장 — infra/README §3 주 "#103 갱신" 참조(시크릿 인벤토리 1→5 최종).
- 로컬 `.env.local`(apps/api)에 `GEMINI_API_KEY` 추가(루트 .env.local 파일럿 키 재사용).
