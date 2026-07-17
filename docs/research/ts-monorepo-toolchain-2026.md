# TS 모노레포 툴체인 2026 현황 — pnpm·turborepo·nx·bun

> wayfinder 티켓 [#79](https://github.com/woosung-dev/cookmark/issues/79) · 1차 출처 조사 · 2026-07-17
> 렌즈 — 회사 표준(여러 서비스에 복제될 표준). 동률이면 "지루하고 검증된" 쪽에 가중치를 둔다(#74 지도 표준 추출 원칙).
> 표기 — ✅ 공식 문서(1차 출처) 확인 / ⚠️ 2차 출처(블로그·벤치마크 글) 기반, 대조 검증 안 됨 / 충돌 시 양쪽 병기

## 핵심 결론

1. **pnpm workspaces와 turborepo는 경쟁 관계가 아니라 계층 관계다**(✅). turborepo는 패키지 매니저의 workspace 기능 "위에" 얹히는 태스크 러너일 뿐이고, 실제 패키지 연결(symlink·`workspace:` 프로토콜 해석)은 pnpm이 한다. "pnpm vs turborepo" 프레이밍 자체가 범주 오류다 — 결정은 "패키지 매니저(pnpm) + 태스크 러너(turborepo 또는 nx)" 두 축을 따로 고른다.
2. **pnpm workspaces가 JS/TS 모노레포의 사실상 기본값이다**(✅). Next.js·Vue·Vite·Material UI 등이 채택, turborepo·nx 문서 전체가 pnpm 예제를 1순위로 제시한다. `workspace:` 프로토콜은 로컬 미해결 시 설치 자체를 실패시켜 registry로 조용히 새지 않는다 — 회사 표준이 원하는 "지루하고 검증된" 축에 정확히 부합.
3. **turborepo가 기본 추천, nx는 트리거 조건부다**(⚠️ 벤치마크 수치는 2차 출처). 소~중 규모 TS 단일 스택(냉파처럼 apps 2~4개)에는 turborepo가 설정 최소·pnpm 그대로 사용 가능해 적합하고, nx는 폴리글랏(JVM·.NET 혼재)·아키텍처 경계 강제·분산 CI가 필요해질 때 트리거된다. 현 냉파 스코프(TS만, apps ≤4)는 turborepo 트리거 미충족.
4. **bun workspaces는 기능상 성숙했지만 "생태계 정합성"이 다르다**(✅+⚠️ 혼합). bun 자체 workspace·`workspace:` 프로토콜·catalogs·`--filter`는 공식 지원되고 turborepo도 bun을 pnpm·npm·yarn과 동등하게 `create-turbo` 1순위 옵션으로 다룬다(✅). 다만 대부분의 서드파티 예제·트러블슈팅 문서는 여전히 pnpm 전제로 쓰여 있다(⚠️, 2차 출처 다수 일치) — "지루하고 검증된" 기준에서는 pnpm이 앞선다.
5. **Next.js 현재 안정 메이저는 16(2025-10-21 출시), 최신 마이너는 16.3(2026-06-29)이다**(✅, nextjs.org 1차 출처). App Router는 v13.4부터 안정이고 신규 프로젝트의 기본값 — Pages Router는 유지보수 모드로 신규 기능이 들어가지 않는다.
6. **Vercel의 모노레포 다중 앱 배포는 "리포 1개 = Vercel 프로젝트 N개" 모델이다**(✅, vercel.com 1차 출처). 각 프로젝트가 독립적인 **Root Directory**를 갖고, 워크스페이스 컨벤션(package.json `workspaces` 또는 pnpm-workspace.yaml)을 따르면 변경 없는 프로젝트의 빌드를 자동 스킵한다. `turbo-ignore`(Ignored Build Step)는 이 자동 스킵의 대체 수단이지 필수 전제가 아니다.
7. **현 냉파 Vercel 프로젝트(`vercel.json` — `framework: null`, `outputDirectory: apps/mobile/build/web`, `api/` 서버리스)와 미래 `apps/web`/`apps/admin` 배포는 자동으로 공존한다**(✅, 구조 확인). Root Directory가 다른 별개 Vercel 프로젝트이므로 서로의 빌드 설정에 영향을 주지 않는다 — "무빌드 정적+함수" 프로젝트라는 특성이 다른 프로젝트의 존재를 막을 이유가 없다.
8. **`packages/config` 관례는 turborepo 공식 예제가 표준을 사실상 확립했다**(✅). `@repo/eslint-config`·`@repo/typescript-config`처럼 스코프 `@repo/*` 아래 도구별 패키지로 쪼개는 패턴이 `create-turbo` 기본 템플릿 자체다 — nx·bun 진영도 이 패턴을 그대로 차용한다.

## 표준 후보 요약

| 도구 | 역할(계층) | 성숙도·채택(2026) | 회사 표준 적합성 | 비고 |
| --- | --- | --- | --- | --- |
| **pnpm workspaces** | 패키지 매니저 + workspace 링킹 | 사실상 기본값. Next.js·Vue·Vite 등 채택, `workspace:` 프로토콜 프로덕션 검증됨(✅) | ★★★★★ 지루하고 검증됨 | 결정은 "쓸지 말지"가 아니라 이미 baseline |
| **turborepo** | 태스크 러너·캐시(=pnpm 위 레이어) | Rust 재작성(2024) 이후 2.0, 활발한 유지보수. Vercel 자사 제품(1차 출처 배포 문서까지 완비)(✅) | ★★★★☆ 소~중 규모 TS 전용에 적합, 설정 최소 | 냉파 규모(apps ≤4, TS 단일 스택)에 정확히 맞는 크기 |
| **nx** | 태스크 러너·캐시·아키텍처 거버넌스·폴리글랏 그래프 | 성숙, 최근 AI 에이전트 인프라(Nx MCP·Self-Healing CI)로 확장 중(⚠️ 포지셔닝은 자사 자료·2차 비교 글 기반) | ★★★☆☆ 트리거 조건부(폴리글랏·경계 강제·분산 CI 필요 시) | 현재는 과설계 — mobile.md §8 "사전 확장 금지"와 같은 원칙 적용 가능 |
| **bun workspaces** | 런타임+패키지매니저+workspace 통합 | 기능 성숙(catalogs·`--filter`·`workspace:` 지원)(✅), 설치 속도 강점(⚠️ 벤치마크 수치는 자사 발표) | ★★☆☆☆ 그린필드면 괜찮으나 생태계 정합성에서 pnpm에 밀림 | turborepo는 1순위 옵션으로 지원(✅)하지만 대다수 3rd-party 문서가 pnpm 전제(⚠️) |

**결론 형태 힌트(#80 그릴링 입력용, 여기서 확정하지 않음)** — "지루하고 검증된" 기준으로는 **pnpm + turborepo** 조합이 현재 스코프에 가장 근접한 후보로 보인다. nx는 apps 수·팀 규모·폴리글랏 요구가 커지면 재검토 대상, bun은 workspace 매니저로는 아직 회사 표준 후보로 이르다(런타임으로서의 bun 채택 여부는 별개 질문).

## 상세 조사

### 1. pnpm·turborepo·nx·bun의 정합 관계

- **계층 구조가 핵심이다.** turborepo 공식 문서: 설치 없이도 기존 `package.json` 스크립트·의존성 선언·`turbo.json` 하나만으로 "adopted incrementally"된다 — 워크스페이스 자체를 turborepo가 만들지 않는다(✅, [turborepo.dev/docs](https://turborepo.dev/docs)). 2차 출처 요약도 동일하게 표현한다 — "pnpm decides how packages link to each other, while Turborepo decides which package scripts run, in what order, and whether they need to run at all"(⚠️, 블로그 요약이나 turborepo 1차 문서와 정합).
- **패키지 매니저 지원 범위** — turborepo는 npm·yarn·pnpm·bun 4종을 `create-turbo` 스캐폴드에서 동등하게 제공한다(✅, [turborepo.dev/docs/getting-started/installation](https://turborepo.dev/docs/getting-started/installation)). "bun 지원은 실험적"이라는 공식 경고 문구는 확인되지 않았다.
- **pnpm workspaces 성숙도** — `pnpm-workspace.yaml` 기반, `workspace:` 프로토콜은 로컬 해결 실패 시 registry로 폴백하지 않고 설치가 실패한다(의도된 안전장치). publish 시 semver 범위로 자동 치환된다. catalogs 기능(버전 통일)도 존재(✅, [pnpm.io/workspaces](https://pnpm.io/workspaces)).
- **turborepo 2.0 스키마 변경** — `turbo.json`의 `pipeline` 키가 2.0(2024-06)부터 `tasks`로 개명됐다(✅, [turborepo.dev/blog/turbo-2-0](https://turborepo.dev/blog/turbo-2-0) 및 GitHub 이슈 교차 확인). 신규 설정 작성 시 `tasks` 키를 쓴다 — 웹상 예제 다수가 구버전 `pipeline` 표기라 혼동 주의.
- **nx의 차별화 포인트** — nx는 `nx.json` 자동 스캐폴드(`npx nx init`)로 태스크 설정 없이도 캐시·affected 감지가 동작한다고 주장하고, JVM·.NET 등 비-JS 생태계까지 그래프에 포함하는 폴리글랏 지원, Nx Cloud의 분산 태스크 실행·Self-Healing CI를 turborepo와의 차별점으로 내세운다(⚠️, nx.dev 자사 소개 + 2차 비교 글 다수 일치 — nx.dev의 turborepo 직접 비교 페이지 `nx.dev/docs/guides/adopting-nx/nx-vs-turborepo`는 존재하나 이번 조사에서 본문 내용까지 1차 대조는 못함, 2차 출처로 표기).
- **성능 벤치마크 수치**(⚠️ 전부 2차 출처, 벤치마크 조건 미상) — 한 2026 벤치마크에서 단일 머신 CI 빌드가 turborepo 25분32초, nx 21분56초(nx가 16% 빠름)로 보고됐고, 분산 CI(4머신)에서는 turborepo가 동적 태스크 분산이 없어 격차가 더 벌어진다는 주장이 있다. bun의 설치 속도는 pnpm 대비 cold install 4~5배, CI warm cache 3배라는 수치도 있다(자사 문서는 npm 대비 28배·yarn v1 대비 12배·pnpm 대비 8배로 더 공격적인 수치를 제시 — 출처 간 배수 자체가 불일치하므로 절대 수치는 신뢰도 낮음, 상대적 우위 방향성만 참고).

### 2. Next.js 안정 버전과 모노레포 배치

- **버전** — Next.js 16이 2025-10-21 GA, 이후 16.1(2025-12-18, Turbopack 파일시스템 캐싱 안정화)·16.2(2026-03-18, 빌드/렌더링 성능 개선)·16.3(2026-06-29, Instant Navigations 등)까지 마이너가 이어졌다(✅, [nextjs.org/blog](https://nextjs.org/blog)). 조사 시점(2026-07-17) 최신 안정은 16.3 계열, 16.3 프리뷰가 진행 중이었다(캐노리 빌드 다수 확인, [github.com/vercel/next.js/releases](https://github.com/vercel/next.js/releases)).
- **App Router** — v13.4(2023)부터 안정, 신규 프로젝트 기본값. Pages Router는 유지보수 모드로 신규 기능이 들어가지 않는다(⚠️, 2차 정리 글 다수가 일관되게 진술 — nextjs.org 공식 라우팅 가이드 원문의 "stable since 13.4" 표현까지는 이번 조사에서 직접 인용 확보 못함, 2차 출처로 표기).
- **모노레포 권장 배치** — turborepo 공식 Next.js 가이드는 `pnpm dlx create-turbo@latest`로 `apps/` 아래 Next.js 앱 여러 개를 두는 구조를 quickstart로 제시한다(✅, [turborepo.dev/docs/guides/frameworks/nextjs](https://turborepo.dev/docs/guides/frameworks/nextjs)). 표준 트리 형태는 `apps/{app1,app2}` + `packages/*` + 루트 `package.json`·`turbo.json`·`pnpm-workspace.yaml` — 냉파의 ADR-0008 트리(`apps/{mobile,api,admin,web}` · `packages/*`)와 이름 수준까지 일치한다.

### 3. Vercel 모노레포 다중 앱 배포 패턴

- **Root Directory가 프로젝트 경계다.** 모노레포의 각 디렉토리를 Import할 때마다 별도 Vercel 프로젝트를 만들고, `Root Directory` 설정으로 그 프로젝트가 보는 서브트리를 지정한다. 한 리포에 연결된 프로젝트 수는 요금제별 상한이 있을 뿐 개수 자체는 자유롭다(✅, [vercel.com/docs/monorepos](https://vercel.com/docs/monorepos)).
- **자동 스킵(Skipping unaffected projects)** — 소스 미변경 시 자동으로 빌드를 건너뛴다. 조건은 (1) GitHub 연결 (2) npm/yarn/pnpm/bun 워크스페이스 컨벤션 준수(`package.json`의 `workspaces` 또는 `pnpm-workspace.yaml`) (3) 각 패키지 `name` 고유 (4) 패키지 간 의존이 `package.json`에 명시. 이 기능은 build slot을 점유하지 않아 `Ignored Build Step`보다 권장된다(✅, 동 출처).
- **`turbo-ignore`** — Vercel이 turborepo 프로젝트 Import 시 자동으로 세팅하는 값들 중 하나가 `Ignored Build Step: npx turbo-ignore --fallback=HEAD^1`이고, Build Command는 `turbo run build`(전역 turbo 자동 제공, 앱 의존성에 `turbo` 추가 불필요) 또는 루트에서 `--filter=<app>`로 특정 앱만 빌드하는 형태다(✅, [vercel.com/docs/monorepos/turborepo](https://vercel.com/docs/monorepos/turborepo)). 즉 "turbo 필터"는 Vercel이 Root Directory로부터 자동 추론하며, 수동 개입 없이도 동작한다.
- **공유 소스 접근** — Root Directory 밖의 소스(공유 `packages/*`)를 빌드에 포함하려면 "Include source files outside of the Root Directory" 옵션이 필요하다 — 2020-08-27 이후 생성된 프로젝트는 기본 활성화(✅, [vercel.com/docs/monorepos/monorepo-faq](https://vercel.com/docs/monorepos/monorepo-faq)).
- **무빌드 정적+함수 프로젝트와의 공존** — 냉파 현재 배포는 리포 루트를 Root Directory로 쓰는 프로젝트다(`vercel.json`: `framework: null`, `buildCommand: null`, `outputDirectory: apps/mobile/build/web`, `api/`가 Vercel 관례 서버리스 디렉토리)(구조 확인, 리포 내부). 미래 `apps/web`을 Root Directory로 갖는 신규 Vercel 프로젝트를 Import하면, 두 프로젝트는 같은 Git 리포에 연결되지만 완전히 독립적인 설정·도메인·빌드 파이프라인을 가진다 — Vercel의 다중 프로젝트 모델 자체가 이 공존을 전제로 설계돼 있다(✅, 위 출처들 종합). 단, 현재 `vercel.json`의 `git.deploymentEnabled.main: false`(#57/#58 자동배포 차단 선례)처럼 프로젝트별 배포 트리거 정책은 프로젝트마다 독립적으로 관리해야 한다는 점은 냉파 쪽 운영 관례이지 Vercel 문서의 요구사항은 아니다.
- **Nx도 Vercel에서 공식 지원된다** — 환경변수 캐싱 관련 알려진 이슈·해결법(`nx.json`의 `namedInputs.sharedGlobals`)이 FAQ에 별도로 존재할 만큼 nx 경로도 1급 지원이다(✅, 동 FAQ).

### 4. `packages/config`형 공유 설정 관례

- turborepo 공식 "내부 패키지 만들기" 가이드가 제시하는 표준 트리는 `packages/{math,ui,eslint-config,typescript-config}` — 각각 `@repo/math`, `@repo/ui`, `@repo/eslint-config`, `@repo/typescript-config`로 스코프 네이밍한다(✅, [turborepo.dev/docs/crafting-your-repository/creating-an-internal-package](https://turborepo.dev/docs/crafting-your-repository/creating-an-internal-package)). 다른 패키지는 해당 스코프 이름으로 이 설정을 그대로 import한다.
- 가이드는 "단일 목적"을 원칙으로 명시한다 — 예: `@repo/tool-specific-config`처럼 도구 하나당 패키지 하나. 여러 도구 설정을 한 패키지에 뭉치지 않는 것이 관례다.
- 이 패턴은 turborepo 전용이 아니라 pnpm+turborepo 생태계 전반의 사실상 표준이며(⚠️ 명시적으로 "업계 표준"이라 선언한 1차 출처는 없으나, `create-turbo` 기본 템플릿이 이 형태이고 nx·bun 진영 예제도 동일 네이밍을 차용한다는 점에서 사실상 표준으로 판단), 냉파 ADR-0008의 `packages/config`("공유 lint·tsconfig·빌드 설정") 계약과 정확히 같은 개념 경계다.

## 냉파에의 시사점

- **ADR-0008이 이미 turborepo 예제와 동형이다.** `apps/{mobile,api,admin,web}` + `packages/{api-client-ts,api-client-dart,types,ui,config,design-tokens}` 트리는 turborepo 공식 템플릿 이름 관례(`@repo/*`)와 구조적으로 일치한다 — "회사 표준은 첫 소비자(냉파)의 실요구에서 추출한다"는 #74 원칙이, 사실은 이미 존재하는 업계 표준과 우연히 수렴해 있는 상태다.
- **`packages/config`의 내용물은 이 조사로 사실상 결정된다** — `@repo/eslint-config` + `@repo/typescript-config` 2개 하위 패키지로 쪼개는 것이 관례이지, 단일 뭉치 설정 패키지가 아니다. #80 그릴링에서 이 세부까지 확정할 수 있다.
- **turborepo가 기본 후보, nx는 트리거 미충족.** 냉파 스코프(`apps/web`·`apps/admin` 2개, TS 단일 스택, 폴리글랏 아님)는 nx가 차별화하는 "다중 팀·폴리글랏·분산 CI" 트리거에 해당하지 않는다 — mobile.md §8 확장 트리거 원칙과 같은 논리로, 지금은 turborepo가 적정 크기다.
- **Vercel 배포는 리포 구조 결정을 기다리지 않아도 된다.** `apps/web`이 실체화되면 별도 Vercel 프로젝트로 Import하고 Root Directory만 지정하면 되므로, 현재 파일럿 배포(`vercel.json` 루트 프로젝트)와 충돌·공존 문제 자체가 발생하지 않는다 — #74 지도의 "상비 가드"(파일럿 계측 접점 금지)와도 자연히 정합한다.
- **미확정으로 남기는 것(#80으로 이월)** — pnpm 버전 pin 정책, Node.js 버전 정책, turborepo `tasks`(구 `pipeline`) 구체 설정, catalogs 채택 여부. 이 조사는 "무엇이 표준적 선택지인가"까지만 다루고 "냉파가 정확히 어떤 버전·설정을 쓸지"는 그릴링 티켓 #80의 몫이다.

## 출처

[pnpm Workspaces](https://pnpm.io/workspaces) · [Turborepo Docs](https://turborepo.dev/docs) · [Turborepo Installation](https://turborepo.dev/docs/getting-started/installation) · [Turborepo Next.js Guide](https://turborepo.dev/docs/guides/frameworks/nextjs) · [Turborepo Internal Packages Guide](https://turborepo.dev/docs/crafting-your-repository/creating-an-internal-package) · [Turborepo 2.0 Blog](https://turborepo.dev/blog/turbo-2-0) · [Nx — Why Nx](https://nx.dev/getting-started/why-nx) · [Nx vs Turborepo](https://nx.dev/docs/guides/adopting-nx/nx-vs-turborepo) · [Bun Workspaces Docs](https://bun.com/docs/install/workspaces) · [Next.js Blog](https://nextjs.org/blog) · [Next.js Releases (GitHub)](https://github.com/vercel/next.js/releases) · [Vercel — Using Monorepos](https://vercel.com/docs/monorepos) · [Vercel — Deploying Turborepo](https://vercel.com/docs/monorepos/turborepo) · [Vercel — Monorepos FAQ](https://vercel.com/docs/monorepos/monorepo-faq) · 리포 내부 확인(`vercel.json`, `packages/*/README.md`, `apps/*/README.md`, `docs/adr/0008-polyglot-monorepo-topology.md`)
