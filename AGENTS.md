# AGENTS.md

This file provides guidance to AGENTS Code (AGENTS.ai/code) when working with code in this repository.

## 무엇을 만드는가

냉파(cookmark) — 냉장고 사진 1장으로 재고를 파악하고, 사용자가 저장한 레시피 북과 매칭해 "오늘 뭐 해먹지"를 끝내는 앱. MVP는 완성 제품이 아니라 **질문 검증기**다 — "사진 1장이 유튜브 검색보다 편한가", "저장 레시피가 실제 선택을 바꾸는가" 두 질문에 답하는 장치이며, n=2 단일 블라인드 파일럿(ADR-0004)으로 검증한다.

코어 루프: 사진 업로드 → 재료 인식 → 재료 체크리스트(confidence 3단) → 레시피 북 매칭 → 제안 최대 3개.

## 리포 상태 (중요)

**이 리포는 "문서가 계약"인 스펙 주도 리포다.** `main` 브랜치에는 코드가 없고 문서(CONTEXT.md·DESIGN.md·ADR·research·agents 가이드)만 있다. 실제 Flutter 코드는 피처 브랜치에 있다.

- `feat/14-core-tracer` — 코어 루프 구현이 가장 완성된 브랜치(아래 구조·명령은 이 브랜치 기준).
- `feat/13-mvp-context7`, `feat/flutter-scaffold-theme` — 스캐폴드·초기 실험.

작업 전 항상 관련 상류 문서를 먼저 읽어라 — 스펙 본문만 읽으면 토큰 필드·단어·섹션 구조를 놓친다. 산출물이 ADR과 충돌하면 조용히 덮지 말고 명시적으로 표면화한다(`docs/agents/domain.md`).

## 스택 · 아키텍처 (ADR-0005, docs/coding-standards.md)

- **Flutter(Dart) 단일 코드베이스**. 우선 타깃 = **Web 빌드**(모바일 브라우저·카톡 URL 공유·설치 0). 후순위 = Android 네이티브(파일럿 후, 같은 코드베이스).
- **로그인·서버 DB 없음** — 클라이언트 로컬 영속(브라우저 스토리지, `shared_preferences`)이 유일한 영속층.
- **LLM 프록시(인식·매칭)는 앱과 분리된 서버리스 함수** — API 키는 절대 클라이언트에 두지 않는다.

경계 규칙(위반 금지):

- **상태 관리**: Flutter 내장(setState/ValueNotifier/ChangeNotifier) + Riverpod까지 허용. Bloc·GetX 등 다른 상태 라이브러리 금지.
- **로컬 영속은 단일 스토리지 모듈로만** — `lib/data/app_storage.dart`. 위젯에서 스토리지 API 직접 호출 금지. 이벤트 로그·레시피 북 읽기/쓰기 경계를 한 곳에 모은다.
- **LLM 호출은 단일 경계 모듈로만** — `lib/llm/recognizer.dart`의 `IngredientRecognizer` 인터페이스. 이것이 앱의 유일한 seam이다. 구현은 서버리스 프록시(`gemini_proxy_recognizer.dart`)이거나 테스트용 페이크(`fake_recognizer.dart`)이며, 위젯은 인터페이스 타입만 안다. 모델명은 환경설정 주입.
- **화면은 메인 · 레시피 북 2개로 고정**(ADR-0001). 코어 루프는 화면 전환 없이 단일 세로 페이지의 섹션 확장/접힘으로 처리 — 앱 내비게이션 마찰을 0에 수렴시켜 측정 순도를 지킨다. 대가로 단일 페이지 상태 기계(온보딩/로딩/체크리스트/제안/에러/세션 복원)의 상태 수가 늘어난다.
- **뭉뚱그림 항목**("반찬통"·"소스류" 등)은 구체 재료로 치환하기 전 매칭에 전송하지 않는다(ADR-0002).
- **수동 수정**(체크리스트 조작 각 1회)은 P2 킬 기준의 계측 단위 — 로그에 유형·경로를 남긴다(ADR-0003).

`lib/` 레이아웃(feat/14-core-tracer): `data/`(영속) · `llm/`(인식 경계) · `models/`(ingredient·app_event) · `screens/`(main_controller·main_page·loading_stage) · `widgets/`(upload_zone·recognition_section·checklist_section·failure_card) · `theme/`(app_colors·app_theme).

## 명령 (코드가 있는 브랜치에서)

```bash
flutter pub get                 # 의존성 설치
dart format .                   # 포맷 (표준 설정 유지)
flutter analyze                 # 린트 (flutter_lints)
flutter test                    # 순수 로직 유닛(라벨 결정·병합·산식·휴리스틱)
flutter test test/models/ingredient_test.dart   # 단일 테스트 파일
flutter test --name '<이름>'    # 이름으로 단일 테스트
flutter run -d chrome           # Web 빌드 로컬 실행(우선 타깃)
flutter build web               # 파일럿 배포 산출물
```

**E2E가 검증의 정본이고 유닛은 보완이다**(coding-standards). E2E는 `integration_test/`에서 Web 타깃으로 돌리며, LLM 경계에 결정적 페이크를 주입한다. 테스트는 외부 행동만 검증한다 — 화면에 보이는 것과 export JSON에 남는 것. 내부 구현 세부에 비의존.

## Agent skills

### Issue tracker

이슈는 GitHub Issues(woosung-dev/cookmark)에서 `gh` CLI로 관리한다. See `docs/agents/issue-tracker.md`.

### Domain docs

단일 컨텍스트 — 루트 `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`. 도메인 개념의 이름은 `CONTEXT.md` 글로서리를 따르고 `_Avoid_` 동의어로 표류하지 않는다.

### Coding standards

코드 작성 규약은 `docs/coding-standards.md`를 따른다 (code-review 스킬의 standards 소스). 새 소스 파일 첫 줄에 역할을 설명하는 한국어 주석 1줄(설정 파일 제외).

### Design

UI 디자인 언어는 루트 `DESIGN.md`가 단일 소스다 (Google Stitch 규약·에이전트 read). Apple식 절제 구조 + 홍시(감) 퍼시먼 액센트. 결정 근거는 `docs/adr/0006`, 도출 과정·아카이브는 `docs/design/`. UI를 만들거나 색을 바꿀 땐 `DESIGN.md`를 먼저 갱신한다.
