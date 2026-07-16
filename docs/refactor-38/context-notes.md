# #38 리팩터 컨텍스트 노트

작업 중 내린 결정과 근거. 세션이 끊겨도 여기서 재개한다. 최신이 위.

## 방향 전환 — 파일럿 후 → D0 전 (2026-07-16)

원래 계획은 "파일럿 후 리팩터"였다. 파운더가 "미루는 게 좋지 않다"며 뒤집었고, 사실 확인 결과 **지금이 오히려 최적 창**이었다.

- **실사용 측정은 D0=7/22부터.** 7/16~7/21 배우자는 관통만·실제 요리 금지(ADR-0004 베이스라인 제약). 지금 코드를 바꿔도 오염시킬 측정이 없다.
- **지금이 freezed 무료 창.** 앱 데이터는 D0 전 전부 초기화(#41). export JSON 와이어 계약을 지금 바꾸면 공짜, D0 후엔 실데이터 쌓여 못 바꿈.
- **D0 안 밀림.** D0 = max(배포완료, 베이스라인 7/21) 후 첫 저녁. 7/21까지 재배포하면 max=7/21 → D0=7/22 유지. 넘기면 밀림. **이게 시한의 근거.**

## 범위 — 3축 정합, 3축 면제 (ADR-0007)

정합 = Riverpod v3 · Failure sealed · freezed. 면제 = Dio · go_router · 3버킷.

면제 근거 요약(전문 ADR-0007 Decision B) — Dio는 인증 토큰이 없어 인터셉터가 집중할 대상이 없다(순가치 음수) · go_router는 화면 2개·Navigator 1곳이라 `?debug` 측정 푸터 깰 위험만 · 3버킷은 feature가 사실상 `main` 1개라 이름만 바뀐 layer-first.

## 미결 결정 기록

### Failure sealed 위치 → `lib/domain/failure.dart`
3버킷 면제라 mobile.md의 `core/error/`를 만들지 않는다. 현 layer-first 구조 유지 → 에러 도메인이니 `lib/domain/`. 별도 `lib/error/` 신설은 최소변경 원칙상 안 함.

### 스토리지·LLM seam 위치 → 현 위치 유지 (`lib/data/storage.dart`·`lib/llm/`)
ADR-0007 Decision A는 "3버킷 도입 시 `shared/`"라고 정했으나, Decision B로 3버킷을 면제하므로 **이동 자체가 없다.** 현 layer-first 위치가 곧 최종. Decision A는 "만약 3버킷을 했다면"의 조건부 기록으로 남는다.

### Riverpod ↔ freezed 순서 → Step 3(Riverpod) 후 Step 4(freezed), 단 재검토 여지
build_runner는 둘 다 선행. freezed를 먼저 하면 모델이 안정된 뒤 그 위에 Riverpod state를 얹어 재작업이 준다는 논리도 있다. Step 3 착수 시 실제 결합도 보고 확정. 현재 계획은 상태 뼈대(Riverpod) 먼저.

## 위험 관리

- **안전망 함정** — E2E 30건 중 24건이 `MainController`(ChangeNotifier)를 직접 쥔다(`core_loop_test.dart:44-68`). Riverpod 전환 전 **반드시** Step 2(안전망 디커플링)를 `lib/` 무변경으로 먼저. 안 그러면 안전망과 대상이 같이 바뀌어 증명이 깨진다.
- **`Recipe` 라운드트립** — D0 초기화 때 레시피는 `previewMerge`로 살아 넘어와야 함(#41). freezed 전환이 toJson/fromJson 바이트 형태를 바꾸면 파운더가 보관한 JSON에서 레시피 복원이 깨진다. 골든 파일 라운드트립 테스트로 방어.
- **CI 없음** — 수동 게이트 도박 방지 위해 Step 1에서 경량 CI 먼저.

## baseline
2026-07-16 `flutter test` = 272 그린. 이게 리팩터 내내 지킬 기준선.
