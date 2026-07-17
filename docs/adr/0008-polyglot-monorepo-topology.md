# 리포 토폴로지를 폴리글랏 모노레포로 확정한다 — apps/mobile만 실체, 나머지는 README 계약

2026-07-17 사용자 결정으로 최상위 구조를 `apps/{mobile,api,admin,web}` · `packages/{api-client-ts,api-client-dart,types,ui,config,design-tokens}` · `contracts/` · `infra/`로 확정한다. BE·FE·모바일 스펙이 동시에 들어올 예정인데 현 구조는 Flutter 앱이 리포 루트에 사는 단일앱이라, 본격 확장 전에 좌표를 고정한다. 지금 실행 가능한 것은 `apps/mobile`(현 루트 Flutter 앱의 이동)뿐이고, 나머지 디렉토리는 README 계약(무엇이 들어오는가 · 어떤 rules가 규율하는가 · 실체화 트리거)만 둔다. 좌표 논쟁을 지금 종결하는 대신 빈 디렉토리 유지비와 배포 배선 재작업을 감수한다. 이 전환은 회귀가 아니라 귀환이다 — `.claude/rules/mobile.md` 원본(`ai-rules`)은 애초에 `apps/*/lib/**` 모노레포 스코프로 작성됐고, 냉파의 `lib/`가 루트라서 frontmatter를 의도적으로 제거해 뒀을 뿐이다(`docs/coding-standards.md` 정본 위계 절).

> **정정 (2026-07-17, [ADR-0009](0009-apps-api-materialization.md))** — 이 ADR의 선언 두 개가 역전됐다. ① **`contracts/`의 "계약 우선"·"상류"**(아래 표 29·30·31·35행) → **코드 우선**(`apps/api`의 Pydantic이 정본, `contracts/`는 발행 지점). 차팅 시점의 좌표 선언보다 채택된 스택이 이긴다 — FastAPI는 구성상 코드 우선이다([#81](https://github.com/woosung-dev/cookmark/issues/81)). ② **`infra/`의 "자동 배포 금지 규약의 정신(#57 선례)"**(36행) → **`apps/api`는 GitHub Actions 자동 배포**. #57을 오독한 문구였다 — #57은 Flutter-Web-on-Vercel 특정 버그(`buildCommand: null` + gitignored `build/web` → 빈 정적 배포) 대응이고 본문 스스로 잠정이라 적었으며, **그 실패 모드는 Cloud Run에 구조적으로 없다**(파이프라인이 이미지를 빌드한다). **`apps/mobile`/Vercel prod의 수동 프리빌드 규약은 그대로 유지된다 — 둘을 한 규칙으로 묶지 말 것**([#88](https://github.com/woosung-dev/cookmark/issues/88)). 아래 본문·표는 정정된 행만 갱신했고, 나머지 서술은 결정 시점 기록으로 둔다.

이 ADR은 **토폴로지·이름·성장 트리거만** 고정한다. ADR-0005의 MVP 범위 결정 — 로그인·서버 DB 없음, LLM 프록시는 앱과 분리된 서버리스 함수 — 는 **역전하지 않는다**(→ **2026-07-17 [ADR-0009](0009-apps-api-materialization.md)가 역전했다.** 아래 문장이 예고한 "자기 ADR"이 그것이다). 서버리스 프록시 3개는 루트 `api/`에 잠정 유지한다(Vercel 파일 관례가 배포 루트의 `api/`를 요구하고, `vercel.json` rewrites가 이를 참조한다). `apps/api` 실체화(진짜 백엔드)는 ADR-0005를 뒤집는 일이므로 미래 wayfinder 지도에서 나올 자기 ADR이 필요하다. 각 앱의 툴체인(Next 버전 · pnpm/turborepo · FastAPI 채택)도 같은 이유로 이 ADR의 범위 밖이며 같은 지도로 간다.

문서(이 ADR + 실행 이슈 [#69](https://github.com/woosung-dev/cookmark/issues/69))는 지금 커밋하고, 물리 이동은 파일럿 판정(~8/5+) 후 **#38 랜딩 후**에 실행한다 — #51 확정대로 "판정이 #38을 연다, 제품 계속이면 다음 작업 전 #38 먼저"이고, #38이 `lib/` 내부를 전면 재배열하므로 최상위 이동과 겹치면 diff가 곱해지고 미머지 WIP(`worktree-fix-ach`)가 rename 너머로 리베이스돼야 한다. 완전 중단(abandon) 판정이면 #38과 함께 실행 이슈 #69도 닫고, 이 ADR은 미실행 결정 기록으로 남는다.

**재결정 (2026-07-17 같은 날, 사용자)** — 위 시점 게이트를 재개봉해 물리 이동(#69)을 즉시 실행한다. 파일럿 검증 결과와 무관하게 프로젝트를 드라이브해야 하는 사업 상황이 근거다. 안전 조건 — main 자동배포 차단(#57)과 순수 rename 덕에 이동은 배포된 파일럿 앱에 무영향이고, 검증은 preview 배포까지만 수행해 prod(파일럿 아티팩트)는 무접촉으로 동결 유지한다. #51의 순서 절반("다음 작업 전 #38 먼저")은 재개봉됐고 #38은 이동 후행이 된다 — 판정이 #38을 여는 절반은 유지된다. 조건부 사망 조항은 실행이 판정에 선행하므로 실효다. 위 단락은 결정 시점의 기록으로 그대로 두며, 재개봉 기록은 #69·#51·#38 코멘트에 있다.

기존 규범과의 화해 — `mobile.md` §8 "사전 확장 금지"와 충돌하지 않는다. §8이 금지하는 것은 미사용 **코드** 구조이고, README 계약은 코드 스캐폴드가 아니라 좌표 선언이며, 회사 표준 템플릿 모양을 명시적 사용자 결정(2026-07-17)으로 채택한 것이다. `docs/agents/domain.md`는 멀티 컨텍스트 관습을 `src/<context>/`로 예시하지만 **이 리포의 컨텍스트 루트는 `apps/<app>/`이다** — `CONTEXT-MAP.md`는 두 번째 `CONTEXT.md`가 실재할 때까지 만들지 않는다(domain.md 자신의 lazy 원칙과 정합). `.claude/rules/backend.md` §11은 `backend/src/`를 전제하는데, **위치는 `apps/api`가 이기고 내부 레이아웃은 §11을 따른다**(`apps/api/src/…`) — gitignored 사본의 경로 표기 갱신은 사용자 몫이다(아래 Consequences). 루트 `idea.md`의 Next.js·SaaS 구상은 ADR-0005 시점에 이미 대체된 역사 기록이라 계약으로 읽지 않는다. 디렉토리 이름은 영문 식별자다 — `CONTEXT.md` 글로서리대로 "cookmark"은 리포·코드 식별자 전용이고 제품명 "냉파"는 코드 좌표에 쓰지 않는다. 마지막으로, 기존 ADR·스펙·티켓 속 파일 경로 표기는 이동 전 좌표의 **시점 기록**이라 소급 수정하지 않는다(ADR-0005의 실측 주석 선례) — 살아있는 운영 문서(AGENTS.md·coding-standards.md·README.md)만 실행 시점에 고친다.

## Considered Options

- **풀 러너블 템플릿(전 앱·패키지 스캐폴드 실행 가능)** — 기각. 판정 전 죽을 수 있는 제품에 4앱·6패키지의 빌드 배선을 미리 만드는 것은 §8이 금지하는 코드 사전 확장의 실체이고, 미사용 의존성·락파일·CI 유지비가 즉시 발생하며, wayfinder가 결정하기 전에 툴체인을 선점한다.
- **최소 이동(`apps/mobile`만, 나머지는 필요할 때)** — 기각(사용자). 좌표가 문서화되지 않으면 다음 앱마다 배치 논쟁이 재발하고, 회사 표준 템플릿 모양과 어긋난다.
- **풀트리 + README 계약(채택)** — 좌표는 지금 고정하고, 실체는 각 디렉토리의 트리거가 연다.

## README 계약 (실행 시 각 디렉토리에 파일로 생성 — 내용은 여기가 정본)

계약 3필드 = 무엇이 들어오는가 / 어떤 rules가 규율하는가 / 실체화 트리거.

| 디렉토리 | 무엇이 들어오는가 | 어떤 rules가 규율하는가 | 실체화 트리거 |
| --- | --- | --- | --- |
| `apps/mobile` | 현 루트 Flutter 앱(유일한 러너블) | `.claude/rules/mobile.md`(frontmatter 복원으로 재수렴) + ADR 경계 규칙 | 즉시 — 이동 실행(#69) 자체 |
| `apps/api` | 진짜 백엔드(서버 DB·인증) — 루트 `api/` 프록시의 승계자 | `.claude/rules/backend.md`(내부 레이아웃 §11 → `apps/api/src/`) — 단 §9는 ADR-0009가 전면 교체, §4는 구조만 채택 | **충족됨 — [ADR-0009](0009-apps-api-materialization.md)**(지도 [#74](https://github.com/woosung-dev/cookmark/issues/74) 산출, 2026-07-17) |
| `apps/admin` | 운영·CS 어드민 웹 | 툴체인 미정 — wayfinder 지도 | 운영할 실데이터(사용자·과금)가 생기는 시점 |
| `apps/web` | 웹 제품·마케팅(파일럿용 Flutter Web 빌드와 별개) | 툴체인 미정 — wayfinder 지도 | Go 이후 웹 제품 결정 |
| `packages/api-client-ts` | `contracts/openapi.yaml`에서 생성한 TS 클라이언트 | 생성물 규칙 — 수기 수정 금지, **`apps/api`의 Pydantic 모델이 정본**(ADR-0009) | `contracts/openapi.yaml` 실재 + TS 소비자(web/admin) 1개 실체화 |
| `packages/api-client-dart` | 같은 스키마의 Dart 클라이언트 | `mobile.md` §8 OpenAPI codegen 행 — Dio 수기 호출과 병존 금지 | **미채택**(ADR-0009) — `apps/mobile`은 수기 Dio + 드리프트 트립와이어. §8 트리거가 구조적으로 영구 미충족이라 재결정 조건은 "계약 드리프트가 실결함으로 발현" |
| `packages/types` | 앱 간 공유 도메인 타입(TS) | 이름은 `CONTEXT.md` 글로서리, 계약은 **`apps/api`가 정본이고 `contracts/`는 발행 지점**(ADR-0009) | 같은 타입을 쓰는 TS 소비자 2개째 |
| `packages/ui` | 공유 웹 UI 컴포넌트 | 루트 `DESIGN.md`(디자인 언어) + `design-tokens` 소비 | web·admin 둘 다 실체 + 중복 컴포넌트 실증 |
| `packages/config` | 공유 lint·tsconfig·빌드 설정 | 툴체인 미정 — wayfinder 지도 | JS/TS 워크스페이스 2개째 |
| `packages/design-tokens` | `DESIGN.md` 토큰의 기계 소비형(JSON 등 파생 생성물) | **토큰 정본은 루트 `DESIGN.md`** — 이 패키지는 파생이지 정본이 아니다 | 토큰이 필요한 2번째 UI 소비자 등장 시 `DESIGN.md`에서 생성 |
| `contracts/` | API 계약의 **발행 지점**(`openapi.yaml` 등) — 정본이 아니라 생성물이 발행되는 곳 | **코드 우선 + 커밋된 스냅샷 + CI 드리프트 가드**(ADR-0009 역전 — 아래 정정 주 참조) | **`apps/api`의 첫 라우트가 생성물로 낳는다**(ADR-0009). 프록시 3개는 수기 문서화하지 않는다 — #75가 폐지를 확정한 코드이고 `.mjs`가 승계 입력이자 정본 |
| `infra/` | IaC·배포 설정(Vercel 단일 프로젝트 이후) | **IaC 미도입 + 프로비저닝 절차 문서**(ADR-0009). `apps/api`는 GitHub Actions 자동 배포 + WIF — **"자동 배포 금지"는 여기 규율이 아니다**(아래 정정 주 참조) | 충족됨 — Cloud Run 도입(ADR-0009). Terraform 도입 트리거 = 환경 2개째 또는 인프라 변경자 2명째 |
| `api/`(루트, 잠정) | **지금 돌아가는** 서버리스 프록시 3개 + `_gemini.mjs` — 이동하지 않는다 | ADR-0005(앱과 분리 · API 키 클라이언트 금지) + `vercel.json` rewrites | **폐지 결정됨** — [ADR-0009](0009-apps-api-materialization.md)가 `apps/api` 전량 승계를 확정. 실행 = 승계 완료 + 파일럿 종료 후 **단순 삭제**([#83](https://github.com/woosung-dev/cookmark/issues/83)). 그때까지 무수정 서빙 |

## Consequences

- 좌표 논쟁이 종결된다 — 다음 앱·패키지가 어디 사는지, 언제 실체화되는지가 문서다. `mobile.md` frontmatter 복원으로 `ai-rules` 원본과 재수렴하고, `backend.md`와의 위치 충돌(`backend/` vs `apps/api`)이 해소된다.
- 부정적 결과를 정직하게 — README뿐인 디렉토리 12개는 처음 보는 눈에 과대 구조로 읽힌다. 배포 배선은 **2회** 재작업된다(이동 시 `vercel.json` outputDirectory·CI working-directory, `apps/api` 실체화 때 또 한 번). 구 레이아웃 worktree 10개의 정리 churn이 실행 이슈에 실린다. 기존 문서의 경로 표기는 전부 이동 전 좌표가 된다(위 시점 기록 선언으로 처리).
- 문서 규칙 — 문서는 존재하지 않는 레이아웃을 서술하지 않는다. AGENTS.md의 레이아웃·명령 재작성과 `coding-standards.md`의 frontmatter 논거 반전은 물리 이동(#69) 시점에 한다. 그때까지 두 문서의 현 서술이 참이다.
- 사용자 관리 항목(gitignored라 리포 PR로 불가, #69 체크리스트에 명시) — `mobile.md` frontmatter 복원, `backend.md` §11 경로 주석, `.claude/settings.json` 훅의 `frontend/**`·`src/**` 패턴 갱신(해당 앱 실체화 때).
- 실행의 전 절차(이동 맵 · 설정 재작성 · 검증 게이트 8단계 · 롤백 · 리스크 5)는 [#69](https://github.com/woosung-dev/cookmark/issues/69)가 정본이다.
