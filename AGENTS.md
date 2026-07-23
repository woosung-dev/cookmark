# AGENTS.md

This file provides guidance to AGENTS Code (AGENTS.ai/code) when working with code in this repository.

## 무엇을 만드는가

냉파(cookmark) — 냉장고 사진 1장으로 재고를 파악하고, 사용자가 저장한 레시피 북과 매칭해 "오늘 뭐 해먹지"를 끝내는 앱. MVP는 완성 제품이 아니라 **질문 검증기**다 — "사진 1장이 유튜브 검색보다 편한가", "저장 레시피가 실제 선택을 바꾸는가" 두 질문에 답하는 장치이며, n=2 단일 블라인드 파일럿(ADR-0004)으로 검증한다.

코어 루프: 사진 업로드 → 재료 인식 → 재료 체크리스트(confidence 3단) → 레시피 북 매칭 → 제안 최대 3개.

## 리포 상태 (중요)

**이 리포는 "문서가 계약"인 스펙 주도 리포다.** 2026-07-16부터 `main`에 Flutter 코드가 있다 — A/B 실험의 두 arm 중 **PR #26(`feat/13-mvp-context7`)이 랜딩됐다**(스펙 #13의 9티켓 전량).

리포는 폴리글랏 모노레포다(`docs/adr/0008`, 실행 [#69](https://github.com/woosung-dev/cookmark/issues/69) 2026-07-17) — **Flutter 앱은 `apps/mobile/`에 산다.** 루트 `api/`는 서버리스 프록시(잠정), 나머지 `apps/*`·`packages/*`·`contracts/`·`infra/`는 README 계약(좌표 선언)이다. BE/FE 로드맵·툴체인은 wayfinder 지도 [#74](https://github.com/woosung-dev/cookmark/issues/74)가 결정 중이다 — 세션 시작 시 지도에서 현재 위치를 잡는다.

- 닫힌 arm — `feat/14-core-tracer`(PR #25, #14 범위만·유닛 48) · `feat/flutter-scaffold-theme`(PR #24). **되살리지 말 것.** #25에는 프록시 오형식 200 응답 시 로딩이 영구 고착되는 결함이 있다.
- 파일럿 배포 URL(정본) — `https://cookmark-woosungdevs-projects.vercel.app`. `cookmark.vercel.app`은 **남의 프로젝트다**(Vercel 전역 네임스페이스).

작업 전 항상 관련 상류 문서를 먼저 읽어라 — 스펙 본문만 읽으면 토큰 필드·단어·섹션 구조를 놓친다. 산출물이 ADR과 충돌하면 조용히 덮지 말고 명시적으로 표면화한다(`docs/agents/domain.md`).

## 스택 · 아키텍처 (ADR-0005 → 배포 타깃은 ADR-0011로 역전, docs/coding-standards.md)

- **Flutter(Dart) 단일 코드베이스**. **파일럿 배포 타깃 = 네이티브 Android APK**(ADR-0011이 ADR-0005의 "Web 빌드로 배포"를 역전 — 웹 폴백 없음, 두 기기 모두 Android라 APK 직접 전달). **스택은 무변경 — 역전 대상은 배포 타깃이지 Flutter 단일 코드베이스가 아니다.** 웹 빌드는 **아직 살아 있다** — 로컬 개발(`flutter run -d chrome`)·E2E(Web 타깃) 실행 편의다. 남은 웹 코드(`web/`·조건부 임포트·배너)는 결함이나 미청소가 아니라 **의도된 잔존**이다 — 정본 목록·근거·정리 트리거는 ADR-0011 웹 폐기 시퀀싱이 쥔다(여기서 다시 열거하면 갈라진다).
- **로그인·서버 DB 없음** — 클라이언트 로컬 영속(브라우저 스토리지, `shared_preferences`)이 유일한 영속층.
- **LLM 프록시(재료 인식·재료 추출·매칭) 3개는 앱과 분리된 서버리스 함수** — API 키는 절대 클라이언트에 두지 않는다.

**Flutter 아키텍처의 정본은 `.claude/rules/mobile.md`다** — 상태 관리·폴더 구조(3버킷)·라우팅·모델(freezed)·네트워크(Dio)·에러 전파. 공개를 원하지 않아 gitignore 될 뿐 **규범이다**. 리포에 없다고 무시하지 말 것. ⚠️ **현재 코드는 여기에 미정합이며 알면서 남긴 부채다** — 파일럿 후 리팩터 트랙([#38](https://github.com/woosung-dev/cookmark/issues/38)). **새 코드는 `mobile.md`를 따른다. 기존 코드 관용구는 선례가 아니라 부채다.**

경계 규칙(위반 금지):

- **상태 관리**: `mobile.md` §0·§3(Riverpod v3 + `riverpod_generator`). 예전 이 줄이 "ChangeNotifier까지 허용"이라 적어 `mobile.md`와 충돌했다 — `mobile.md`가 이긴다(2026-07-16 화해).
- **로컬 영속은 단일 스토리지 모듈로만** — `apps/mobile/lib/data/storage.dart`. 위젯에서 스토리지 API 직접 호출 금지. 이벤트 로그·레시피 북 읽기/쓰기 경계를 한 곳에 모은다. **ADR이 정본이라 `mobile.md`의 feature별 `repositories/`보다 우선한다** — P2 킬 기준의 원본 데이터가 여기서 나오므로 흩어지면 안 된다.
- **LLM 호출은 단일 경계 모듈로만** — 재료 인식·재료 추출·매칭을 **모두** 감싸는 인터페이스 하나가 앱의 유일한 seam이다. **프록시 엔드포인트는 3개지만 seam은 1개**다(테스트가 결정적 페이크를 꽂는 지점이 1곳이라는 뜻 — 두 수를 같이 세지 않는다). 구현은 서버리스 프록시이거나 테스트용 페이크이며, 위젯은 인터페이스 타입만 안다. 모델명은 환경설정 주입. 구체 파일·클래스명은 arm 랜딩 시 확정한다 — 계약이 규정하는 건 경계의 존재와 seam 수이지 식별자가 아니다(지도 #27 티켓 #30).
- **화면은 메인 · 레시피 북 2개로 고정**(ADR-0001). 코어 루프는 화면 전환 없이 단일 세로 페이지의 섹션 확장/접힘으로 처리 — 앱 내비게이션 마찰을 0에 수렴시켜 측정 순도를 지킨다. 대가로 단일 페이지 상태 기계(온보딩/로딩/체크리스트/제안/에러/세션 복원)의 상태 수가 늘어난다.
- **뭉뚱그림 항목**("반찬통"·"소스류" 등)은 구체 재료로 치환하기 전 매칭에 전송하지 않는다(ADR-0002).
- **수동 수정**(체크리스트 조작 각 1회)은 P2 킬 기준의 계측 단위 — 로그에 유형·경로를 남긴다(ADR-0003).

**현재** `apps/mobile/lib/` 레이아웃(랜딩된 arm — `mobile.md` 3버킷이 **아니다**, 위 부채 참조): `data/`(영속 — `storage.dart`) · `domain/`(ingredient·app_event·suggestion·recipe·backup·vague_heuristic 등) · `llm/`(LLM seam — `llm_gateway.dart` 인터페이스 + `proxy_llm_gateway`·`fake_llm_gateway`) · `ui/`(main_controller·main_page·recipe_book_* + `widgets/`) · `image/`(768px 리사이즈) · `platform/`(인앱 브라우저 판별) · `theme/`.

**목표** 레이아웃은 `mobile.md` §1(`features/`·`shared/`·`core/`). 단 단일 스토리지 모듈·단일 LLM seam을 3버킷 어디에 두는지는 **미결**이다 — 둘 다 도메인을 알아서 `core/`의 "도메인을 모르는 인프라" 정의와 어긋난다. 리팩터 트랙([#38](https://github.com/woosung-dev/cookmark/issues/38))의 첫 결정이다.

## 명령 (`apps/mobile/`에서 실행)

```bash
cd apps/mobile                  # Flutter 패키지 루트 (ADR-0008)
flutter pub get                 # 의존성 설치
dart format .                   # 포맷 (표준 설정 유지)
flutter analyze                 # 린트 (flutter_lints)
flutter test                    # 순수 로직 유닛(라벨 결정·병합·산식·휴리스틱)
flutter test test/models/ingredient_test.dart   # 단일 테스트 파일
flutter test --name '<이름>'    # 이름으로 단일 테스트
flutter run -d chrome           # Web 빌드 로컬 실행(개발·E2E 편의 — 파일럿 배포 타깃 아님)
flutter build web               # Web 산출물(로컬·E2E용, 파일럿 배포 아님)
# 파일럿 배포 산출물 = 네이티브 릴리스 APK (ADR-0011). 런북 docs/pilot/native-apk-runbook.md.
#   dart-define(COOKMARK_API_BASE) 누락 시 네트워크가 조용히 죽는다(#134). key.properties 없으면 릴리스만 시끄럽게 실패(#141).
flutter build apk --release --dart-define=COOKMARK_API_BASE=https://cookmark-woosungdevs-projects.vercel.app
```

이 게이트(format·analyze·test + E2E)는 `.github/workflows/mobile.yml`로 매 PR(`apps/mobile/**` paths 필터)·main push(무필터 백스톱)에서도 자동 실행된다(#59·#69).

**E2E가 검증의 정본이고 유닛은 보완이다**(coding-standards). E2E는 `integration_test/`에서 **아직 Web 타깃으로** 돌리며, LLM 경계에 결정적 페이크를 주입한다 — 파일럿은 네이티브 APK로 배포하지만 CI/E2E의 네이티브 타깃 전환은 미결(파일럿 후 정리 트랙 — 지도 #129가 잔여 fog로 남김, 미착수). 그래서 웹 빌드가 살아 있어야 E2E가 돈다(ADR-0011 웹 폐기 시퀀싱과 정합). 실기기 전용 검증(카메라·실사진·카톡 설치)은 #65 D0 스모크 몫이다. 테스트는 외부 행동만 검증한다 — 화면에 보이는 것과 export JSON에 남는 것. 내부 구현 세부에 비의존.

## Agent skills

### Workflow — 세션 종료 시 다음 단계 제안 (필수)

이 리포의 작업은 matt 스킬 플로우를 따른다. **아이디어 → `/grill-with-docs`(구체화) → 크고 안개 낀 효력이면 `/wayfinder`(결정 지도, 세션당 티켓 1개) → 지도 닫힘 → `/to-spec`(지도를 스펙으로 붕괴) → `/to-tickets`(수직 슬라이스 분해) → 티켓당 `/implement`(새 세션, 내부 `/tdd`·`/code-review`)**. 버그는 `/diagnosing-bugs`, 외부 유입 이슈는 `/triage`, 유지보수는 `/improve-codebase-architecture`.

- **모든 작업 세션은 마지막 응답에서 플로우 상의 현재 위치와 다음 슬래시 명령을 제안하고 끝낸다.** 예 — "다음은 새 세션에서 `/wayfinder 74 #77`" · "지도가 닫혔다 — 새 세션에서 `/to-spec`(지도 #74 참조) 후 **같은 세션에서 이어서** `/to-tickets`" · "티켓 #N이 ready-for-agent다 — 새 세션에서 `/implement #N`".
- `/wayfinder`·`/to-spec`·`/to-tickets`·`/implement`는 **사용자 명시 호출 전용**이다 — 에이전트가 대신 호출하지 말고, 입력할 명령을 정확한 인자와 함께 제시한다.
- 현재 위치 판별 — 열린 `wayfinder:map` 이슈(프런티어 = open·unblocked·미할당 자식)와 `ready-for-agent` 이슈를 조회해 판단한다. 지도가 닫혔고 스펙이 없으면 `/to-spec` 차례, 스펙만 있으면 `/to-tickets` 차례, 티켓이 있으면 `/implement` 차례다.
- 컨텍스트 위생 — `/to-spec`→`/to-tickets`는 한 컨텍스트에서 연달아(컴팩트 금지), `/implement`는 티켓마다 새 세션.

### Issue tracker

이슈는 GitHub Issues(woosung-dev/cookmark)에서 `gh` CLI로 관리한다. See `docs/agents/issue-tracker.md`.

### Domain docs

단일 컨텍스트 — 루트 `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`. 도메인 개념의 이름은 `CONTEXT.md` 글로서리를 따르고 `_Avoid_` 동의어로 표류하지 않는다.

### Coding standards

코드 작성 규약은 `docs/coding-standards.md`를 따른다 (code-review 스킬의 standards 소스). 새 소스 파일 첫 줄에 역할을 설명하는 한국어 주석 1줄(설정 파일 제외).

### Design

UI 디자인 언어는 루트 `DESIGN.md`가 단일 소스다 (Google Stitch 규약·에이전트 read). Apple식 절제 구조 + 홍시(감) 퍼시먼 액센트. 결정 근거는 `docs/adr/0006`, 도출 과정·아카이브는 `docs/design/`. UI를 만들거나 색을 바꿀 땐 `DESIGN.md`를 먼저 갱신한다.
