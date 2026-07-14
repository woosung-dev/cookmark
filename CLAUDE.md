# CLAUDE.md

## Agent skills

### Issue tracker

이슈는 GitHub Issues(woosung-dev/cookmark)에서 `gh` CLI로 관리한다. See `docs/agents/issue-tracker.md`.

### Domain docs

단일 컨텍스트 — 루트 `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.

### Coding standards

코드 작성 규약은 `docs/coding-standards.md`를 따른다 (code-review 스킬의 standards 소스).

### Design

UI 디자인 언어는 루트 `DESIGN.md`가 단일 소스다 (Google Stitch 규약·에이전트 read). Apple식 절제 구조 + 홍시(감) 퍼시먼 액센트. 결정 근거는 `docs/adr/0006`, 도출 과정·아카이브는 `docs/design/`. UI를 만들거나 색을 바꿀 땐 `DESIGN.md`를 먼저 갱신한다.
