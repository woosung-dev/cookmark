# #99 api-3 계약 스냅샷 + CI 드리프트 가드 — 체크리스트

티켓 정본은 [#99](https://github.com/woosung-dev/cookmark/issues/99), 결정 정본은 [ADR-0009](docs/adr/0009-apps-api-materialization.md) 계약 절(#81) + `.claude/rules/backend.md` §9.2. 직전 티켓 #97(스캐폴드)은 PR #105로 머지됐다 — 이 티켓은 그 위에 얹는다.

## 구현

- [x] 브랜치 `feat/99-contract-guard` + 작업 문서 갱신
- [x] RED — `tests/test_contract.py` 먼저(동기·드리프트 검출·결정성), 실패 확인(`ModuleNotFoundError: scripts`)
- [x] GREEN — `scripts/export_openapi.py`(render/write/drift + `--check`)
- [x] 앱 import 순서 지뢰 제거 — conftest의 CORS env를 모듈 스코프로(컨텍스트 노트 참조)
- [x] `contracts/openapi.yaml` 생성·커밋 (생성물 헤더 = 수기 수정 금지)
- [x] `.github/workflows/api.yml` — 드리프트 가드 + schemathesis 스텝
- [x] `contracts/README.md`·`apps/api/README.md` — 명령·경로를 실체와 일치

## AC 검증

- [x] 스냅샷 커밋 + 재생성 결정적 — 연속 2회 실행 `diff` 0 실측 + 프로세스 2개(`PYTHONHASHSEED` 0/12345) 동일 테스트
- [ ] 스키마 변경 + 스냅샷 미갱신 → CI 빨간불 (실증 1회) — 로컬 실측 완료(exit 1 + diff + 재생성 명령), **CI 실증은 PR에서**
- [ ] schemathesis가 CI에서 현 라우트 전체에 green — 로컬 실측 완료(1/1 operation · 9 케이스 · Coverage+Fuzzing)
- [x] contracts README가 "코드 우선·생성물·수기 수정 금지" 반영 (명령·경로 실체 일치)

## 마무리

- [x] 인루프 게이트 — `ruff format` · `ruff check` · `mypy src/ scripts/` · `pytest` 전체 green (12 passed, `.env.local` 유무 양쪽)
- [ ] `/code-review` + 지적 반영
- [ ] 시맨틱 커밋 → push → PR → CI green → 티켓 코멘트
