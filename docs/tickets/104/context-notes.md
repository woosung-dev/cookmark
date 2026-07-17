# #104 컨텍스트 노트 — 결정과 근거

다음 세션(사람·에이전트)이 재도출 없이 이어받기 위한 기록. AC·설계 원문은 이슈 #104와 스펙 #96, 결정 정본은 ADR-0009 데이터 이전 절(#86).

## 무엇을 만드나

로그인한 기존 로컬 사용자가 로컬 레시피 북 전체를 **1회 bulk 요청**으로 계정에 올린다. 서버가 전량 성공을 정직하게 확인해 줘야 클라이언트가 로컬을 지운다(성공 확인 후 로컬 삭제, 실패 시 유지). 클라이언트 UX(배너·확인·로컬 삭제)는 범위 밖(#83 BE 소비 접점 이후).

## 핵심 설계 결정

- **별도 `src/migration/` 모듈 = 시한부 격리.** recipes 안에 섞지 않고 독립 모듈로 둔 이유는 **제거 용이성**이다. 제거 트리거(파일럿 2계정 이전 완료) 발화 시 `rm -rf src/migration/` + main.py include 1줄 + 테스트 파일 + 스냅샷 재생성이면 끝난다. recipes(영구 코드)는 무변경. 시한부 표기는 각 파일 헤더 주석 + 모듈 docstring에 제거 트리거로 남긴다.
- **LLM seam 무의존 = 재추출 없음의 구조적 보증.** `RecipeImportService`는 `RecipeBookRepository`만 주입받고 `BaseLLMService`를 **아예 모른다**. "등록 중 LLM 호출 0회"(AC)가 테스트뿐 아니라 **타입 수준에서** 성립한다. 로컬에서 이미 1회 추출된 재료를 그대로 수용한다 — 재추출은 비용·결과 표류만 낳는다.
- **원자성 = N개 add → 1회 commit.** 트랜잭션 경계는 Service(§3). `RecipeBookRepository.add()`는 항목마다 flush하지만 commit은 서비스가 마지막에 1회만 한다. 중간 항목이 flush에서 실패하면 commit에 도달하지 못하고, 세션 컨텍스트 매니저가 롤백 → 저장 행 0. (recipes create의 추출 실패 502-미저장이 같은 자동 롤백에 의존 — 선례.)
  - 실패는 서비스가 `SQLAlchemyError`를 잡아 `RecipeImportFailed`로 변환하고, 라우터가 **500**으로 문서화해 응답한다(친절한 한국어 detail + 계약 명시). 성공/실패를 클라이언트가 명확히 가른다.
- **스코프드 Repository 재사용.** `RecipeBookRepository(session, owner_id=account.id)` — owner는 생성 시점에 1회 박히고 `add()`가 owner를 인자로 받지 않으므로, 다른 계정으로 오염될 방법이 구조적으로 없다(§12.2). 새 repository를 만들지 않고 recipes 것을 그대로 쓴다(§12 격리가 이미 계약).

## 중복 URL 정책 (#103이 #104로 넘긴 결정)

**무처리 — dedup 없음, unique 제약 없음, 보낸 그대로 보존.** 근거.

- 이전 대상은 **갓 로그인한 빈 계정**이다 — 서버측 기존 행 충돌이 없다.
- 로컬 레시피 북은 **이미 url을 dedup 키로 병합**한다(모바일 백업 병합, #103 노트 line 17) — 배치 내 중복이 실무상 생기지 않는다.
- 티켓 #104는 dedup·unique를 요구하지 않는다. #103 노트가 "409 표면이 계약에 선지불된다"고 경고했다 — unique는 **영구 스키마 변경**이라 POST /recipes까지 바꾸는 범위 이탈이고, 시한부 이전에 영구 제약을 심을 이유가 없다.
- 따라서 클라이언트가 만에 하나 중복을 보내면 별도 행으로 저장된다(garbage-in-preserved). 사전 dedup된 데이터에 대한 시한부 이전이라 감수한다.

## 응답 형태

- **성공 = 201 + `list[RecipeResponse]`.** recipes create/list와 동형(별도 응답 스키마 불요). 서버 배정 id를 담은 N개 항목이 "전량 성공"의 명확한 증거다. `RecipeResponse`는 recipes.schemas에서 재사용(migration→recipes 단방향 의존이라 순환·제거 지장 없음).
- **실패 = 500**(원자적 등록 실패, 아무것도 저장 안 됨) · **401**(무세션) · **400**(깨진 본문) · **422**(빈 배치·항목 스키마 위반).

## 함정 (재발 방지)

- **본문 라우트의 숨은 400** — FastAPI는 본문 JSON 디코드를 의존성 해석보다 먼저 한다. 깨진 본문은 401이 아니라 400이다(#103 실측·PATCH도 발현). 본문 받는 이 라우트도 **400 문서화 필수** — 안 하면 schemathesis "Undocumented status code"로 CI 빨강.
- **schemathesis는 무인증 fuzz** — `CurrentAccount`가 본문 검증(422)보다 먼저 401을 내므로 fuzzing이 DB(자리표시자 URL)·서비스에 도달하지 않는다. 신규 라우트는 401/400 문서화만 하면 통과, 신규 exclude 불요.
- **NUL 원자성 벡터** — Postgres text/asyncpg는 `\x00`을 거부한다. 중간 항목 title에 NUL을 넣어 mid-batch flush 실패를 결정적으로 유발한다(실제 예외 타입은 실측으로 catch 절 확정 — SQLAlchemyError 래핑 여부).
- **두 계정 분리는 Bearer** — `idp.login` 후 `client.cookies.clear()`, 헤더가 쿠키를 이긴다(recipes 테스트 선례).
- **⚠️ 정적 서브경로 vs `/{id}` 충돌 = schemathesis "Unsupported methods" 실패**(CI 실측, 첫 push에서 잡힘). 처음엔 `POST /recipes/import`로 뒀는데, `/recipes/import`가 `/recipes/{recipe_id}`와 겹친다 — 정의 안 된 메서드(`PATCH /recipes/import`)가 `{recipe_id}` 라우트로 흘러 `recipe_id="import"` → UUID 파싱 422를 내고, schemathesis는 미정의 메서드에 **405**를 기대하므로 실패한다. 로컬 pytest·mypy·드리프트는 전부 green이라 **schemathesis만 잡는다.** 해법 = 전용 `/migration/recipes` 네임스페이스로 이동(recipes `{recipe_id}:uuid` 변환기 도입은 영구 recipes 코드를 시한부 이유로 바꾸는 것이라 기각 — 격리 원칙). 교훈: 리소스에 `/{id}` 라우트가 있으면 그 아래 정적 서브경로(`/recipes/*`)를 새로 파지 말 것.

## 제거 트리거 (시한부)

**파일럿 가구 2계정의 이전이 모두 완료되면 이 이전 코드를 제거한다**(ADR-0009 데이터 이전 절 — "두 계정 이전 완료 시 제거"). 제거 대상: `src/migration/` 전체 · `main.py`의 migration_router include 1줄 · `tests/test_recipes_import.py` · 계약 스냅샷 재생성. recipes 도메인은 무변경(의존 방향이 단방향이라 영향 0).

## 파운더 확인 후보 (해석 결정)

- **빈 배치 = 422**(현재) vs **201 no-op**. 스펙은 빈 배치 거동을 규정하지 않는다. 422를 택한 근거 — 클라이언트는 로컬에 레시피가 있을 때만 부른다(ADR), "N개 등록"은 N≥1을 함의, 코드베이스의 `min_length` 관용구와 정합. 빈 배치가 와도 데이터 유실은 없다(로컬이 비어 있으니 422→유지→무해). 201 no-op이 더 관대하나 "성공했는데 아무것도 안 올라감"의 모호함이 생긴다. #103의 파운더 확인 관행을 따라 남긴다.
- **원자적 실패 catch 범위 = `SQLAlchemyError`**(넓히지 않음). DB 경로의 현실적 실패는 전부 SQLAlchemyError다(제약·운영·데이터 오류·커넥션 단절, NUL 포함 — 테스트로 실증). `Exception`으로 넓히면 프로그래밍 버그를 500으로 삼킨다. 다른 타입의 mid-item 실패가 나도 **원자성은 무관하게 성립**한다(commit이 1회뿐이라 부분 저장 경로 자체가 없다) — 제너릭 500이 될 뿐이고 성공/실패 구분(201 vs 비201)은 유지된다.
