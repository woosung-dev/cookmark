# #38 리팩터 체크리스트 — mobile.md 정합 (Riverpod·Failure·freezed)

브랜치 `worktree-fix-ach` · 시한 **7/21**(D0=7/22 유지) · 근거 ADR-0007 · baseline 272 그린(2026-07-16).

각 단계는 mobile.md §0.1 인루프 4단계로 검증 — ① `dart run build_runner build --delete-conflicting-outputs`(codegen 있을 때만) → ② `dart format --output=none --set-exit-if-changed lib/ test/` → ③ `flutter analyze --fatal-infos` → ④ `flutter test`. E2E(`integration_test`)는 chromedriver 필요라 게이트에서.

## Step 0 — 방향 전환 문서 정정 ✅
- [x] `coding-standards.md` "파일럿 후" → "D0 전" 정정
- [x] ADR-0007 착수 시점·freezed 와이어 계약 정정
- [x] #38 코멘트 2건(안전망 전제 정정 + 착수 시점 정정)
- [x] `docs/refactor-38/` checklist·context-notes 세팅

## Step 1 — 경량 CI 배선 ✅
- [x] `.github/workflows/flutter.yml` — pub get → format check → analyze --fatal-infos → test (커밋 40adb76)
- [x] 로컬 format·analyze·test 그린으로 검증 (push는 PR 시)
- 근거 — 154+24 테스트 흔드는데 수동 게이트는 도박(ADR-0007). E2E는 chromedriver라 CI 제외, 유닛/위젯만.

## Step 2 — 안전망 디커플링 (Riverpod 절대 선행) ✅
- [x] `waitForPhase`(controller.addListener/.phase) → `waitForVisible`(UI 관측) 이관
- [x] `pumpApp` 반환 void화 — controller 참조는 내부 주입(105·113)에만
- [x] url_launcher fake 주입 — openRecipe 버튼 탭이 launchUrl로 headless hang (context-notes 참조)
- [x] **`lib/` 무변경 상태로** E2E 30 + 유닛 272 그린 = 순수 이관 증명
- 주의 — 여기서 `lib/`를 건드리면 안전망 변경과 대상 변경이 섞여 증명이 깨진다.

## Step 3 — freezed (모델 먼저 · 순서 뒤집음 2026-07-16 · Step 4 선행)
- [x] deps — flutter_riverpod·riverpod_annotation·freezed·json_serializable·dev: build_runner·riverpod_generator·riverpod_lint (커밋 4ade2c7)
- [x] `analysis_options.yaml` — riverpod_lint 플러그인 (mobile.md §0.1)
- [x] `Recipe` (커밋 f5c6194) — json_serializable 기본 와이어 일치, 라운드트립 보존(#41)
- [x] `suggestion` (MissingIngredient·Suggestion·SuggestionSelection) — 조건부 필드 `@JsonKey(includeIfNull:false)`로 와이어 보존
- [ ] `ingredient` — 계산 팩토리(.recognized/.added) named factory로, 조건부 toJson (와이어 바뀜·D0 전 안전·테스트 조정)
- [ ] `session_state` (Ingredient 의존 — Ingredient 후)
- [ ] `app_event` — 명명 생성자 12개 → sealed union (가장 복잡, export JSON 와이어 계약)
- [ ] `backup`(AppEvent 의존) · `debug_metrics`(직렬화·copyWith 없어 실익 낮음·선택)
- [ ] 상태 클래스(MainState 등 — Riverpod Notifier용)
- 단순 모델은 json_serializable 기본이 현재 와이어와 일치. 각 전환 후 인루프 4단계.

## Step 4 — Riverpod + riverpod_lint + Failure (freezed 상태 클래스 위에)
- [ ] `lib/domain/failure.dart` — `sealed class Failure` + 변종 (3버킷 면제·layer-first, context-notes). `LlmFailure` → `Failure` 변환 gateway 1곳
- [ ] `MainController`·`RecipeBookController`·`BackupController` → `@riverpod` Notifier + `AsyncValue` (상태는 freezed MainState)
- [ ] `main.dart` 수동 DI → `ProviderScope` + `ProviderScope(retry:)` (mobile.md §4)
- [ ] 위젯 → `ConsumerWidget`, build서 `ref.watch`·핸들러서 `ref.read`
- [ ] 유닛 154 → `ProviderContainer`+`overrideWith` 재작성
- [ ] 인루프 4단계 + E2E 30 그린

## Step 5 — 재배포 + 관통 재확인 (7/21까지)
- [ ] `flutter build web` 산출물 생성
- [ ] `?debug` 측정 푸터 동작 확인(면제한 go_router가 이걸 안 건드렸는지)
- [ ] 배포(정본 URL `cookmark-woosungdevs-projects.vercel.app`)
- [ ] 폰 실사진으로 코어 루프 관통 재확인
- [ ] **#41 절차로 관통 이벤트 초기화**(D0 전) — 이건 파운더 직접

## 완료 조건 (mobile.md §9)
- 인루프 4단계 전부 그린 · E2E 30 그린 · 유닛 재작성분 그린
- 경계 — 단일 스토리지/LLM seam은 `shared/`(면제로 3버킷 이동 안 하면 현 위치 유지, ADR-0007 Decision B) · Failure 변환 repository 1곳
