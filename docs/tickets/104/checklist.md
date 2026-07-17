# #104 api-8 데이터 이전 bulk 가져오기 — 체크리스트

티켓 정본은 [#104](https://github.com/woosung-dev/cookmark/issues/104), 상류는 스펙 [#96](https://github.com/woosung-dev/cookmark/issues/96) + ADR-0009 데이터 이전 절(그릴링 [#86](https://github.com/woosung-dev/cookmark/issues/86)). 선행 #103(서버 레시피 북 CRUD) 머지 완료(PR #111). 결정 로그는 context-notes.md.

## 구현

- [x] 작업 문서(checklist·context-notes) — #104로 신규 작성
- [x] `src/migration/` 신규 모듈 — **시한부**(파일럿 2계정 이전 완료 시 모듈째 삭제). recipes 스코프드 Repository 재사용, LLM seam 무의존(재추출 없음의 구조적 보증)
  - [x] `schemas.py` — `RecipeImportItem`(url·title·**이미 추출된 ingredients**)·`RecipeImportRequest`(min_length=1)
  - [x] `exceptions.py` — `RecipeImportFailed`(원자적 등록 실패)
  - [x] `service.py` — `RecipeImportService`(RecipeBookRepository만 주입, LLM 없음). N개 add → 1회 commit(트랜잭션 경계=Service). 실패 시 rollback→도메인 예외
  - [x] `dependencies.py` — 세션에서 owner 꺼내 스코프드 repo 조립(LLM 미주입)
  - [x] `router.py` — `POST /api/v1/migration/recipes`, 201=list[RecipeResponse]·400·401·500 문서화, tag=migration
- [x] `main.py` — migration_router 등록
- [x] `contracts/openapi.yaml` 재생성 커밋

## AC 검증 (tests/test_recipes_import.py — 실 DB 관통)

- [x] N개 항목 bulk 등록 → 전부 요청 계정 스코프 저장, 재료가 보낸 그대로 보존(빈 배열·특수 재료 포함)
- [x] 등록 중 LLM seam 호출 0회(`fake_llm.extracted_titles == []` + 구조적: 서비스에 LLM 없음)
- [x] 중간 항목 실패(NUL 바이트) → 전체 롤백, 그 배치 URL 저장 행 0
- [x] 응답이 성공(201)/실패(≠201) 명확히 구분
- [x] 무세션 401
- [x] 깨진 본문 400(본문 라우트 함정 — #103 실측)
- [x] 빈 배치·잘못된 항목 → 422
- [x] 교차 테넌트 격리 — A가 넣은 항목이 B 목록에 안 보임
- [x] 시한부 표기(제거 트리거) 존재 — 모듈 docstring + 이 문서

## 게이트

- [x] `uv run ruff format --check .` · `uv run ruff check .` · `uv run mypy src/ scripts/`
- [x] `uv run pytest -v` 전량 green
- [x] `uv run python scripts/export_openapi.py --check` green
- [x] /code-review 2축
