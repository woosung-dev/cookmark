# 코딩 스탠다드

MVP(질문 검증기) 코드 작성 규약. 2026-07-13 문답으로 확정, 같은 날 Flutter 전환(ADR-0005)으로 개정.
2026-07-16 개정 — Flutter 아키텍처의 정본을 `.claude/rules/mobile.md`로 위임(아래).

## 정본 위계 — 어느 문서가 이기나

- **Flutter 아키텍처·스택·구조** = `.claude/rules/mobile.md`가 정본이다. 상태 관리·폴더 구조·라우팅·모델·네트워크·에러 전파는 그 문서를 따른다. 이 파일은 그것을 **반복하지 않는다** — 두 곳에 쓰면 갈라지고, 실제로 갈라졌었다(2026-07-16 발견).
  - `mobile.md`는 공개를 원하지 않아 gitignore 될 뿐, **규범이다**. 리포에 없다고 무시하면 안 된다.
  - 출처는 공용 규칙 리포 `ai-rules`이고 여러 프로젝트에 배포된다. 그 원본은 frontmatter로 적용 범위를 `mobile/**/*`·`apps/*/lib/**/*`(모노레포 레이아웃)로 제한한다. 앱이 리포 루트 `lib/`에 살던 시기에는 그 패턴에 안 걸려 frontmatter를 의도적으로 제거했었다(사용자, 2026-07-16). ADR-0008 이동으로 앱이 `apps/mobile/lib/`에 살게 되어 그 근거가 반전됐다 — **frontmatter를 복원해 원본과 재수렴한다**(gitignored 사본이라 사용자 관리, [#69](https://github.com/woosung-dev/cookmark/issues/69)). 같아진 것도 유실이 아니라 설계다.
- **측정 순도를 지키는 경계 규칙**(단일 스토리지 모듈·단일 LLM seam·화면 2개)은 ADR이 정본이고 `mobile.md`보다 우선한다 — 이것들은 아키텍처 취향이 아니라 파일럿이 무엇을 재는지에 직결된다.
- 도메인 용어 = `CONTEXT.md` 글로서리. UI 언어 = `DESIGN.md`. 화면·의미 구조 = ADR·스펙.

## ⚠️ 현재 코드는 `mobile.md`에 미정합이다

파일럿 코드(PR #37)는 `ChangeNotifier` + `ListenableBuilder`로 짜여 있고 Riverpod·go_router·
freezed·Dio가 없다. `mobile.md`가 요구하는 3버킷(`features/`·`shared/`·`core/`)도 아니다.

**왜 이렇게 됐나 — 규칙이 코드보다 나중에 왔다.** `.claude/rules/`는 2026-07-15 **23:40**에
설치됐고, 두 arm은 그 전에 끝났다(PR #25 16:55 · PR #26 20:29). 그 세션들의 프롬프트에
`mobile.md`는 **존재하지 않았다** — 안 지킨 게 아니라 없었다. 문서 모순(아래 §상태·경계)은
실재하지만 **이 미정합의 원인이 아니다**. 둘은 별개다.

**지금은 알면서 남긴 부채다.** 파일럿 D0(2026-07-22)가 코앞이고 코드는 이미 배포·검증돼
돌아간다. 파일럿은 제품 질문 2개를 재는 장치이지 아키텍처를 재지 않는다. 정합 리팩터는
**파일럿 후** 별도 트랙이다([#38](https://github.com/woosung-dev/cookmark/issues/38)).
E2E 30건이 행동을 고정하고 있어 안전망은 있다 — 그 안전망은 파일럿 데드타임에 ChangeNotifier에서 UI 관측으로 디커플됐고(#60), CI(#59)가 매 PR·main push에서 이걸 돌린다.

**새 코드를 쓸 때는 `mobile.md`를 따른다.** 기존 코드의 관용구를 근거로 삼지 말 것 —
그건 부채이지 선례가 아니다.

## 스택

- Flutter(Dart) 단일 코드베이스. 우선 타깃 = **Web 빌드**(모바일 브라우저·URL 공유 배포), 후순위 = Android 네이티브(파일럿 후, 같은 코드베이스).
- 로그인·서버 DB 없음 — 클라이언트 로컬 영속이 유일한 영속층(Web 빌드에서는 브라우저 스토리지 기반).
- LLM 프록시(인식·매칭)는 앱과 분리된 서버리스 함수 — API 키는 클라이언트에 두지 않는다.

## 도구

- **dart format + flutter_lints** — 포맷·린트. 규칙 집합 배선은 `mobile.md` §0.1을 따른다(`analysis_options.yaml`이 비어 있으면 린터가 아무것도 강제하지 않는다).
- **flutter test** — 순수 로직(라벨 결정·병합·산식·휴리스틱) 유닛.
- **integration_test** — E2E(Web 타깃 실행). 검증의 정본은 E2E이고, 유닛은 보완이다.

## 상태·경계

- **상태 관리는 `mobile.md` §0·§3을 따른다** — Riverpod v3 + `riverpod_generator`. 이 파일이 예전에 "Flutter 내장(ChangeNotifier)까지 허용"이라 적어 `mobile.md`의 "`ChangeNotifierProvider` 신규 금지"와 정면 충돌했다. **`mobile.md`가 이긴다** (2026-07-16 화해).
- **`go_router`는 면제한다** (`mobile.md` §5 예외, [#50](https://github.com/woosung-dev/cookmark/issues/50)) — ADR-0001의 화면 2개 상한이 유지되는 동안. 현 구조(`MaterialApp` + `home: MainPage` + 단일 `Navigator.push`)를 유지한다. 근거 — in-app 네비게이션 그래프가 1개 엣지(MainPage→RecipeBookPage)뿐이라 `routes.dart`/`router.dart` 분리가 풀 순환이 없고, 웹 뒤로가기는 Navigator 1.0의 히스토리 통합으로 이미 동작하며, 1개 엣지짜리 라우터 + `go_router_builder` codegen은 순수 비용이다. **재검토 트리거 = `apps/mobile/test/architecture/navigation_test.dart`** — 명령형 화면 push가 2건이 되면 실패해 go_router 재결정을 강제한다. 새 ADR은 만들지 않는다(파일럿 한정 툴링 면제).
- 아래 둘은 **ADR이 정본이라 `mobile.md`의 구조 규칙보다 우선한다** — 측정 순도에 직결되기 때문이다:
  - 로컬 영속 접근은 **단일 스토리지 모듈**을 통해서만 — 위젯에서 스토리지 API 직접 호출 금지. 이벤트 로그·레시피 북의 읽기/쓰기 경계를 한 곳에 모은다. P2 킬 기준의 원본 데이터가 여기서 나온다.
  - LLM 호출은 **단일 경계 모듈**을 통해서만 — 테스트 페이크 주입 지점이자 유일한 seam. 프록시 엔드포인트는 3개지만 seam은 1개다. 모델명은 환경설정 주입.
  - `mobile.md`의 feature별 `repositories/`로 이 둘을 쪼개면 경계가 흩어진다. 3버킷 위에서 이 둘을 **어디에 두는지는 미결**이다 — 리팩터 트랙의 첫 결정이다([#38](https://github.com/woosung-dev/cookmark/issues/38)).

## 테스트

- 외부 행동만 검증한다 — 화면에 보이는 것과 export JSON에 남는 것. 내부 구현 세부에 비의존.
- E2E는 LLM 경계에 결정적 페이크를 주입해 돌린다.

## 네이밍·문서

- 도메인 개념의 이름은 루트 `CONTEXT.md` 글로서리를 따른다 — `_Avoid_` 동의어로 표류 금지.
- 새 소스 파일 첫 줄에 역할을 설명하는 한국어 주석 1줄(설정 파일 제외).
