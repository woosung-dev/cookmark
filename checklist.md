# #144 기록 초기화 — 체크리스트

티켓 정본은 [#144](https://github.com/woosung-dev/cookmark/issues/144), 상류는 스펙 [#140](https://github.com/woosung-dev/cookmark/issues/140)(지도 [#129](https://github.com/woosung-dev/cookmark/issues/129) · 결정 [#136](https://github.com/woosung-dev/cookmark/issues/136) · 절차 [#41](https://github.com/woosung-dev/cookmark/issues/41) · 단일맹검 ADR-0004). 결정 로그는 context-notes.md.

목표 한 줄 — **파운더가 D0 직전에 관통 테스트가 남긴 기록을 앱 안에서 지운다. 이벤트 0, 레시피는 그대로.**

## 구현

- [x] 작업 문서(checklist·context-notes) — #144로 갱신
- [x] `lib/data/storage.dart` — `clearPilotRecord()` 신설(이벤트·세션·백업시각·1회성 플래그 삭제, 레시피 보존). `@visibleForTesting clear()`와 **별개 API**
- [x] `lib/ui/main_controller.dart` — `resetPilotRecord()`. 스토리지 호출 + 메모리 상태를 갓 부팅 상태로. 푸터 열림은 유지
- [x] `lib/ui/widgets/debug_footer.dart` — `onReset` 콜백 + 초기화 버튼
- [x] `lib/ui/main_page.dart` — 확인 다이얼로그 1단계(취소 시 무변경)

## AC 검증

- [x] 푸터 안에 초기화 버튼 — 배우자는 푸터를 못 여니 버튼도 못 본다
- [x] 이벤트·세션·백업시각·1회성 플래그 소멸 · 레시피 잔존
- [x] 확인 1단계 — 취소하면 아무것도 안 지워진다
- [x] 초기화가 스토리지 모듈을 통과 — 위젯이 영속 API 직접 호출 0
- [x] 초기화 후 정상 = **이벤트 0**(웹의 "이벤트 1"에서 반전 — 재import가 사라졌다)
- [x] E2E — 이벤트 쌓고 레시피 저장 후 초기화 → 푸터 이벤트 0 · 레시피 잔존
- [x] E2E — 취소하면 무변경
- [x] 유닛 — 보존 경계를 **키 단위로** 고정
- [x] export(클립보드) 무변경 — 초기화 절차에서 export가 빠진다

## 마무리

- [x] 인루프 게이트 — `dart format` · `flutter analyze --fatal-infos` · `flutter test`
- [x] E2E — `scripts/e2e.sh` 전량(core_loop · api_cutover) green
- [x] `/code-review` 2축(Standards·Spec) → 지적 반영(날고 있던 호출의 이벤트 누수 · DESIGN.md 다이얼로그 · dialogTheme 토큰 · 보존 경계 구조화 · 작업 문서 완성)
- [x] 반영 후 게이트 재실행 — format · analyze · test(427) · E2E 전량 green
- [ ] 커밋
