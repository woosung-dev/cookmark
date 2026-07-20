# #142 LLM 경계 오형식 200 하드닝 — 체크리스트

티켓 정본은 [#142](https://github.com/woosung-dev/cookmark/issues/142), 상류는 스펙 [#140](https://github.com/woosung-dev/cookmark/issues/140)(지도 [#129](https://github.com/woosung-dev/cookmark/issues/129) · 완화 근거 [#133](https://github.com/woosung-dev/cookmark/issues/133)). 결정 로그는 context-notes.md.

목표 한 줄 — **프록시가 오형식 200을 줘도 사용자가 영원한 로딩에 갇히지 않는다.**

## 구현

- [x] 작업 문서(checklist·context-notes) — #142로 갱신
- [x] `lib/llm/llm_gateway.dart` — `normalizeLlmFailures` 추가(경계 계약의 강제 지점, 광범위 catch)
- [x] `lib/llm/proxy_llm_gateway.dart` — recognize·extractIngredients·match 3개 전부를 감싼다
- [x] `lib/llm/api_v1_llm_gateway.dart` — `on TypeError` 열거 4곳을 같은 헬퍼로 치환(두더지잡기 제거)
- [x] `test/architecture/llm_gateway_contract_test.dart` — 계약 트립와이어(리뷰 반영)
- [x] `main_controller.dart` 무변경 — #143과 세션이 겹치지 않게 (수정은 게이트웨이 안에서 끝난다)

## AC 검증

- [x] 유닛 — 본문이 Map이 아님 / `usage` 없음 / 항목 모양이 다름 × recognize·extract·match 9종 (`test/llm/proxy_llm_gateway_test.dart`)
- [x] 유닛 — 정규화되지 않은 실패가 새지 않는다(계약 자체를 고정하는 테스트)
- [x] E2E — 오형식 200 페이크(실 `ProxyLlmGateway` + `MockClient`)로 코어 루프: 인식 실패 카드 + "다시 시도"가 화면에 보인다
- [x] E2E — 매칭 단계에서도 같은 오형식 200이 실패 카드로 해소된다(고착 아님)
- [x] 새 화면 0개 — 기존 `failure-card`·`failure-retry`·`failure-manual` 재사용

## 마무리

- [x] 인루프 게이트 — `dart format` · `flutter analyze` · `flutter test`
- [x] E2E — `scripts/e2e.sh integration_test/core_loop_test.dart`
- [x] `/code-review` 2축(Standards·Spec) → 지적 반영(계약 트립와이어·sweep 확장·매칭 재시도 실증·한국어 종결 콜론)
- [x] 커밋
