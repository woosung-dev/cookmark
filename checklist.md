# #97 api-1 스캐폴드 + 검증 하네스 — 체크리스트 (walking skeleton 로컬)

계획: `~/.claude/plans/97-dazzling-manatee.md`. 티켓 정본은 [#97](https://github.com/woosung-dev/cookmark/issues/97), 결정 정본은 ADR-0009 + `.claude/rules/backend.md`. (직전 태스크 ADR-0008 체크리스트는 전량 완료 — 잔여 파운더 수동 항목은 #69에 남아 있다.)

## 구현

- [x] 브랜치 `feat/97-api-scaffold` + 작업 문서 갱신
- [x] uv 프로젝트 (pyproject·deps·ruff/mypy/pytest 설정·`.python-version` 3.13) — `uv sync` 통과
- [x] RED — tests(conftest·test_health·test_cors) 먼저, 실패 확인
- [x] GREEN — `core/config.py`(NoDecode CORS·SecretStr) · `common/database.py`(statement_cache_size=0·expire_on_commit=False) · `health/router.py` · `main.py` · alembic async 배선 + 빈 베이스라인
- [x] 인루프 게이트 — `ruff format` · `ruff check` · `mypy src/` · `pytest` 전체 green
- [x] `.github/workflows/api.yml` — mobile.yml 동형(PR paths 필터 + main 무필터 백스톱)
- [x] `apps/api/README.md` 실체화 문서로 갱신 + 로컬 `.env.local` 생성(gitignored)

## AC 검증

- [x] 로컬 uvicorn + 허용 origin에서 health 200 (CORS preflight 통과)
- [x] 비허용 origin 브라우저 차단 — 수동 확인 1회 (Playwright)
- [x] ASGI + testcontainers 실 Postgres 통합 테스트 ≥1 green
- [x] `alembic upgrade head` 실 DB 적용 (테스트 컨테이너에서 증명)
- [x] PR CI에서 pytest·ruff·mypy 전부 통과 — run 29581508224, pytest `7 passed in 9.23s`(러너 testcontainers 실구동)
- [x] CORS 기본 빈 목록·origin 하드코딩 없음

## 마무리

- [x] `/code-review` + 지적 반영 — 2축(Standards·Spec) 하드 위반 0, 반영 3건(5863bd4)
- [x] 시맨틱 커밋 4개 → push → PR #105 → CI green → 티켓 코멘트
