# HANDOFF — 모노레포 이동 완료 (ADR-0008 · #69)

> 새 세션은 이걸 먼저 읽고 `AGENTS.md`·`checklist.md`·`context-notes.md`를 보조로 본다. 직전 효력(목업 풀 패리티)은 PR #68로 머지 완료 — 그 HANDOFF는 git 이력에 있다.

## 지금 어디까지 왔나 (2026-07-17)

**리포는 폴리글랏 모노레포다.** Flutter 앱 = `apps/mobile/`(순수 rename 이동, 92파일 100% similarity), 서버리스 프록시 = 루트 `api/`(잠정), 나머지 `apps/*`·`packages/*`·`contracts/`·`infra/` = README 계약. 결정은 ADR-0008, 실행 절차·재개봉 기록은 #69(+#51·#38 코멘트).

- 시점 게이트는 2026-07-17 사용자 재결정으로 재개봉됐다 — 파일럿 판정을 기다리지 않고 실행. #38(3버킷 리팩터)은 이동 **후행**이 됐고 판정 게이트는 유지된다.
- `worktree-fix-ach`(#38 WIP 7커밋)는 origin에 백업됨. 정정 전 착수 세션의 실행 설계 문서 2건은 #38 코멘트에 박제.
- worktree 10개 제거·merged 브랜치 정리·사석 arm 2개는 `archive/*` 태그로 박제 후 삭제.

## 배포 상태 (중요)

- **prod는 무접촉** — 정본 URL(`https://cookmark-woosungdevs-projects.vercel.app`)은 이동 전 파일럿 빌드를 계속 서빙한다. 파일럿(D0 7/22~8/5)은 예정대로.
- 새 배포 경로는 preview 배포로 증명됨(#69 코멘트에 URL 증거) — break-fix가 필요하면 `(cd apps/mobile && flutter build web)` → 루트에서 `vercel build` → `vercel deploy --prebuilt`(prod는 `--prod` 추가). main 자동배포 차단(#57)은 불변.

## 다음 일

1. **파운더 수동 항목(#69 체크리스트)** — `.claude/rules/mobile.md` frontmatter 복원(`apps/*/lib/**` 스코프), `backend.md` §11 경로 주석(`apps/api/src/`), D0 운영(#65·#41).
2. **BE/FE 로드맵 wayfinder 지도** — 각 앱의 존재 이유·툴체인(Next·pnpm/turbo·FastAPI)·`contracts/` 실체화를 결정. 코드를 안 옮기므로 언제든 차팅 가능.
3. **#38** — 판정 후(판정이 연다, #51 유지). 경로는 `apps/mobile/` 접두로 읽고 WIP 리베이스 필요(#38 코멘트 참조).

## 함정 (깨면 아픈 것)

- `.vercelignore`는 404 지뢰다 — 부정 패턴 금지·디렉터리 패턴 루트 앵커 필수(파일 헤더 주석이 정본). bare `web/`·`build/` 패턴 절대 금지.
- `apps/mobile`에서만 `flutter test` — `test/architecture/navigation_test.dart`가 cwd 의존.
- 루트에 `lib/`를 "복원"하지 말 것 — 구 레이아웃 기억(문서·이력)은 이동 전 시점 기록이다.
- 파일럿 하드 제약 유지 — `storage.dart`·`app_event.dart`·`debug_metrics.dart`·`debug_footer.dart`·`loading_stage.dart`(이제 `apps/mobile/lib/` 아래) 무수정, 명령형 push ≤1.
