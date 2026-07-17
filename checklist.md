# ADR-0008 모노레포 전환 — 결정 박제 체크리스트

브랜치 `docs/adr-0008-monorepo-topology`. 계획: `~/.claude/plans/1-crystalline-mitten.md`. 물리 이동은 이 효력의 범위 밖 — 실행은 [#69](https://github.com/woosung-dev/cookmark/issues/69)가 정본이다.

## 결정 박제 (docs-only)

- [x] 실행 이슈 #69 생성(실행 설계 전문 — 이동 맵·설정 재작성·검증 8게이트·롤백·리스크 5)
- [x] #69 ← #38 blocked_by 배선(native dependency, database id) + API로 검증
- [x] `docs/adr/0008-polyglot-monorepo-topology.md` 신규 — 토폴로지·범위 가드(ADR-0005 비역전)·시점·기존 규범 화해·README 계약 표 13행
- [x] AGENTS.md §리포 상태 — ADR-0008 포인터 1줄(레이아웃·명령 서술은 이동 전까지 유효 명시)
- [x] idea.md — 역사 표기 헤더(계약이 아니라 역사)
- [x] checklist.md·context-notes.md 재작성(직전 효력 PR #68은 머지 완료로 종결)

## EXIT 게이트

- [ ] PR 생성 → CI(gate·e2e) green — 코드 무변경이므로 통과 확인만
- [ ] 머지(관례대로 merge commit)
- [ ] 머지 후 `gh issue view 69` 라벨·blocked_by 재확인

## 이 효력이 하지 않는 것

- 물리 이동(git mv·vercel.json·.vercelignore·ci.yml) — #69, 판정 후.
- `docs/coding-standards.md` line 10 수정 — 현 서술이 오늘은 참, 교체 문안은 #69에.
- README 계약 파일 12개 생성 — 실행 시점(#69 PR-1), 내용 정본은 ADR-0008 표.
- BE/FE 로드맵(툴체인·앱 존재 이유) — 별도 wayfinder 지도.
