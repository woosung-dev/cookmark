# Context Notes — ADR-0008 폴리글랏 모노레포 전환 (결정 박제)

자율결정 감사 추적. 결정/근거 1줄씩 append. 계획: `~/.claude/plans/1-crystalline-mitten.md`.

## 상위 프레이밍

- **이동이 아니라 결정 박제다.** 사용자 결정(2026-07-17) 4건 — ①시점=지금 계획+ADR만·실행은 판정 후 ②스코프=템플릿 전체 트리 ③깊이=풀트리+README 계약(러너블은 apps/mobile뿐) ④절차=구조 직행·BE/FE 로드맵은 wayfinder. 이 세션 산출물은 ADR-0008 + 실행 이슈 #69 + 포인터 2줄이 전부다.

## 결정 로그

- **왜 지금 물리 이동을 안 하나** — 파일럿 D0=7/22 시작·~8/5 종료, #51 잠긴 결정("판정이 #38을 연다, 제품 계속이면 다음 작업 전 #38 먼저"). 이동은 배포 기계(vercel.json·.vercelignore)를 건드려 break-fix 절차를 흔들고, 미머지 `worktree-fix-ach`(#38 WIP 7커밋)가 rename 리베이스를 강요당한다. #38 먼저 → 이동은 그 뒤 단일 클린 커밋.
- **#69 ← #38 배선은 native dependency(database id)** — issue-tracker.md 정본 idiom. `ready-for-agent`를 지금 붙여도 안전한 이유 = frontier 규칙이 open blocker를 자동 배제 → #38 닫히는 순간 자동 부상. 파일럿 판정은 이슈가 아니지만 #51이 #38에 판정 게이트를 인코딩하므로 전이적으로 커버.
- **`api/`(프록시 3개) 루트 잠정 유지** — Vercel 파일 관례가 배포 루트의 `api/`를 요구(.vercel project rootDirectory=null). `apps/api` 실체화 ADR이 승계를 결정할 때까지 이동 금지. ADR-0008 표에 잠정 행으로 박제.
- **ADR-0008은 ADR-0005를 역전하지 않는다** — 토폴로지·이름·트리거만. 로그인·서버 DB 없음·프록시=서버리스는 유지. apps/api 실체화·툴체인(Next·pnpm/turbo·FastAPI)은 미래 wayfinder 지도 산출 ADR의 몫. 근거 = 도메인 규칙 "ADR과 충돌하면 조용히 덮지 말고 표면화"(domain.md).
- **README 계약 파일은 실행 시점 생성** — git이 빈 디렉토리를 못 담고, 지금 만들면 docs-only PR이 아니게 된다. 내용은 ADR-0008 표가 정본, 파일 생성은 #69 PR-1.
- **coding-standards.md line 10 무수정** — "frontmatter 제거는 루트 lib/ 때문" 서술이 오늘은 참. 반전의 성립 조건이 물리 이동 자체라 교체 문안(복원+재수렴)은 #69 커밋 3에 실었다.
- **기존 ADR 경로 표기 소급 수정 안 함** — ADR은 시점 기록(ADR-0005 L14 실측 주석 선례). 살아있는 운영 문서(AGENTS·coding-standards·README)만 실행 시점에 고친다.
- **탐사 근거(하중 파일 직접 검증)** — .vercelignore 헤더 규칙 2개(부정 패턴 금지·루트 앵커 필수, 404 실측 2026-07-16)·vercel.json outputDirectory·ci.yml 무 working-directory·`test/architecture/navigation_test.dart:20` cwd 의존·`scripts/e2e.sh` 자기 위치 기준. 전부 #69 리스크/게이트에 반영.
- **mobile.md 원본이 이미 `apps/*/lib/**` 스코프** — 이 전환은 회귀가 아니라 귀환. frontmatter 복원은 gitignored라 사용자 관리 항목으로 #69에 명시.
