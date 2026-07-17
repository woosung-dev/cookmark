# #101 체크리스트 — LLM 승계 (재료 인식·추출·매칭 + 매칭 % 실산출)

플랜 정본: `~/.claude/plans/101-structured-bird.md` (승인 2026-07-18).

## 준비

- [x] 브랜치 `feat/101-llm-succession` 생성 (main에서)
- [x] worktree `.venv` 동기화 (`uv sync`)
- [x] `uv add google-genai httpx` — py.typed 확인(2.12.1), lock 동커밋

## 설정 배선 (원자 — 전부 한 커밋)

- [x] `src/core/config.py` — gemini_api_key(SecretStr)·gemini_model·단가 2필드
- [x] `tests/conftest.py` — GEMINI_API_KEY env (+ cache_clear는 모듈 생성 커밋에서)
- [x] `scripts/export_openapi.py` — placeholder 맵에 GEMINI_API_KEY
- [x] `.github/workflows/api.yml` — schemathesis env에 GEMINI_API_KEY
- [x] `apps/api/.env.local` — 로컬 키 추가 (커밋 아님)
- [x] `uv run pytest -v` green 유지 확인 (34 passed)

## TDD — 산식

- [x] `tests/test_llm_scoring.py` red 확인
- [x] `src/llm/scoring.py` + `src/llm/service.py` seam 타입 → green (11 passed)

## TDD — 원가·Gemini 경계

- [x] `tests/test_llm_usage.py` red 확인
- [x] `src/llm/gemini.py` read_usage → green (5 passed)
- [x] gemini.py SDK 호출부·예외 매핑 + `src/common/prompts.py` + exceptions.py + dependencies.py (+ conftest cache_clear)

## TDD — 라우트

- [x] `tests/test_llm_routes.py` (401 → 200 → 422/502) + `tests/llm.py` 페이크 + conftest `fake_llm`
- [x] `src/llm/schemas.py`·`router.py`·`main.py` 배선 → green (18 passed — Base64Bytes 관대 디코더는 after-validator로 보강)
- [x] 계약 스냅샷 재생성 + `tests/test_contract.py` green

## 게이트·검증

- [x] ruff format · ruff check · mypy · export --check · pytest 전체 (68 passed)
- [x] 로컬 schemathesis 재현 — 미문서 400 발견·문서화 후 546/546 통과
- [x] 실 Gemini 스모크 (`scripts/smoke_llm.py`) — 총 $0.00146, image_tokens=1064 재현. 결과는 context-notes
- [x] README·infra 시크릿 인벤토리 문서
- [ ] `/code-review` → 반영 → push → PR
