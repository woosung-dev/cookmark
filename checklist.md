# ADR-0008 모노레포 전환 — 체크리스트 (결정 박제 + 물리 이동 실행)

계획: `~/.claude/plans/1-crystalline-mitten.md`. 실행 정본은 [#69](https://github.com/woosung-dev/cookmark/issues/69).

## 1부 — 결정 박제 (PR #70, 머지 완료)

- [x] 실행 이슈 #69 생성 + #38 blocked_by 배선
- [x] `docs/adr/0008-polyglot-monorepo-topology.md` 신규
- [x] AGENTS.md 포인터·idea.md 역사 표기

## 2부 — 재개봉 + 물리 이동 (2026-07-17 사용자 재결정)

- [x] 게이트 재개봉 기록 — #69 blocked_by 해제, #69·#51·#38 코멘트, ADR-0008 재결정 주석
- [x] step 0 — worktree 10개 제거, merged 브랜치 정리, `worktree-fix-ach` origin 백업, 사석 arm `archive/*` 태그 후 삭제, #38 설계 문서 이슈 박제
- [x] PR-1 (#71) — 계약 README 12개 + ADR 재결정 주석
- [x] PR-2 커밋 1 — 순수 rename 92파일 → `apps/mobile/` (전부 100%)
- [x] PR-2 커밋 2 — `mobile.yml`(working-directory·paths 필터·main 무필터)·`vercel.json`·`.vercelignore`·`.gitignore` 분할
- [x] PR-2 커밋 3 — AGENTS.md·coding-standards:10·README 토폴로지·HANDOFF·apps/mobile/README

## EXIT 게이트 (#69 검증 프로토콜, prod 무접촉 수정안)

- [ ] `cd apps/mobile` 인루프 4게이트 green (format·analyze·test)
- [ ] E2E 로컬 green (`bash apps/mobile/scripts/e2e.sh`)
- [ ] PR CI — `mobile` 워크플로 실제 실행 green (스킵 아님 확인)
- [ ] `flutter build web` + `vercel build` parity (`static/index.html` 존재·diff clean·함수 3개 존재)
- [ ] preview 배포 스모크 4종 (`/` 200 · SPA rewrite · 프록시 POST · GET rejectNonPost)
- [ ] ~~prod 재배포~~ — 재결정으로 제외, 파일럿 아티팩트 동결 유지
- [ ] 머지 후 main push 무필터 CI green → #69 해소 코멘트·클로즈

## 파운더 수동 항목 (gitignored — PR 불가)

- [ ] `.claude/rules/mobile.md` frontmatter 복원 (`mobile/**/*`·`apps/*/lib/**/*`)
- [ ] `.claude/rules/backend.md` §11 경로 주석 → `apps/api/src/`
