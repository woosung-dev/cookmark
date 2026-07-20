# #143 계측 트리거 네이티브 등가물 — 체크리스트

티켓 정본은 [#143](https://github.com/woosung-dev/cookmark/issues/143), 상류는 스펙 [#140](https://github.com/woosung-dev/cookmark/issues/140)(지도 [#129](https://github.com/woosung-dev/cookmark/issues/129) · 결정 [#136](https://github.com/woosung-dev/cookmark/issues/136) · 단일맹검 ADR-0004). 결정 로그는 context-notes.md.

목표 한 줄 — **파운더가 네이티브에서 측정 수치를 볼 수 있고, 배우자에게는 잔상조차 남지 않는다.**

## 구현

- [x] 작업 문서(checklist·context-notes) — #143으로 갱신
- [x] `lib/domain/debug_metrics.dart` — `debugFooterEnabled()`(`Uri.base` 판정) 삭제
- [x] `lib/ui/main_controller.dart` — `debugEnabled` 주입 훅 삭제, `showsDebugFooter`를 `late final`에서 세션 한정 가변 상태 + `toggleDebugFooter()`로
- [x] `lib/ui/main_page.dart` — 앱바 타이틀을 `GestureDetector(onLongPress:)`로 감싼다(`Key('app-title')`)
- [x] `lib/ui/widgets/debug_footer.dart` 무변경 — 여는 방법만 바꾸고 내용은 그대로다

## AC 검증

- [x] 롱프레스로 열린다 — E2E `측정 푸터는 앱바 타이틀 롱프레스로만 열린다 (#143, ADR-0004)`
- [x] 기본 숨김 · 트리 부재 — E2E `제스처 전에는 측정 푸터가 트리에 없다 — 숨김이 아니라 부재다 (#143)` (`?debug` 시절의 부재 단언을 그대로 승계)
- [x] 그 세션 한정 — E2E `앱을 다시 띄우면 푸터는 도로 숨는다 — 그 세션 한정이다 (#143)` (신규)
- [x] 푸터 내용 무변경 — 렌더되는 수치·표시 문자열 `'측정 (debug)'` 그대로. `debug_footer.dart`는 첫 줄 헤더 주석만 고쳤다(리뷰 반영, 동작 0)
- [x] `?debug` 경로 제거 — `apps/**/*.dart`에 `debugFooterEnabled`·`debugEnabled`·`?debug` 잔재 0건
- [x] E2E가 트리거를 우회하지 않는다 — `pumpApp`의 `debug` 파라미터를 지웠고(양쪽 E2E 파일), 푸터를 여는 경로는 `openDebugFooter()` 헬퍼의 `tester.longPress`뿐이다
- [x] `?debug` 유닛 테스트 삭제 — `test/domain/debug_metrics_test.dart`의 `debug 쿼리 파라미터 (ADR-0004)` 그룹을 대상 코드와 함께 지웠다(417 → 415)
- [x] #41 리허설 E2E도 제스처 경로로 이관 — 주입 훅이 없으니 구조적으로 강제된다

## 마무리

- [x] 인루프 게이트 — `dart format`(0 changed) · `flutter analyze --fatal-infos`(No issues) · `flutter test`(415)
- [x] E2E — `scripts/e2e.sh` 전량(core_loop · api_cutover) green
- [x] 레드 선행 확인 — 구현 전 E2E에서 정확히 제스처 의존 3건만 실패
- [x] `/code-review` 2축(Standards·Spec) → 지적 반영(접근성 semantics 누수 · 헤더 주석 · 닫는 쪽 단언 · `restartApp` 추출 · 세션 테스트 과대주장 제거)
- [x] 반영 후 게이트 재실행 — `dart format` · `flutter analyze` · `flutter test` · `scripts/e2e.sh` 전량 green
- [ ] 커밋
