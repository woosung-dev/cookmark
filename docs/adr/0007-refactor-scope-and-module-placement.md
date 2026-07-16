# mobile.md 정합 리팩터 — 선별 정합·나머지 면제, 모듈 배치 확정 (#38)

파일럿 코드는 `.claude/rules/mobile.md`에 8개 축에서 미정합이다(상태관리·폴더·라우팅·모델·네트워크·에러·린트·codegen). 원인은 위반이 아니라 부재다 — 규칙이 코드보다 늦게 왔다(`.claude/rules/` 설치 2026-07-15 23:40 vs 세 arm 완료 16:55·20:29, `docs/coding-standards.md` §미정합). 이 ADR은 리팩터 트랙(#38)의 두 미결을 확정한다 — (A) 단일 스토리지 모듈·단일 LLM seam을 3버킷 어디에 두는가, (B) 8축을 전량 정합시킬 것인가. 결론 — **Riverpod·freezed·Failure는 정합하고, Dio·go_router·3버킷은 근거를 붙여 면제한다.** 착수는 파일럿 실사용 시작(D0=2026-07-22) 전, 7/21까지다 — 지금이 유일한 창이기 때문이다(Consequences).

## Decision A — 단일 스토리지 모듈·단일 LLM seam은 `shared/`

mobile.md §1의 3버킷 판정(2단 질문)을 정직하게 돌리면 예외 없이 답이 나온다.

| 질문 | `Storage`(`lib/data/storage.dart`) | `LlmGateway`(`lib/llm/llm_gateway.dart`) |
| --- | --- | --- |
| 도메인을 아는가 | 안다(`AppEvent`·`Recipe`·`SessionState`) → `core/` 탈락 | 안다(`Ingredient`·`Recipe`·`Suggestion`) → `core/` 탈락 |
| 한 기능만 아는가 | 아니다(main·recipe_book·backup 전부) | 아니다(main·recipe_book) |
| **답** | **`shared/`** | **`shared/`** |

`core/storage/`가 mobile.md에 있는 건 "도메인을 **모르는** 저장소"(SharedPreferences 래퍼) 자리이고, 냉파의 `Storage`는 도메인을 알아 거기 해당하지 않는다. AGENTS.md·coding-standards §경계가 "feature별 `repositories/`로 쪼개면 경계가 흩어진다"고 규정한 것과도 충돌하지 않는다 — `shared/`의 단일 모듈은 쪼개지 않는다.

## Considered Options (Decision A)

- **`shared/`에 통째로** — 채택. 판정 규칙 정직 적용, ADR 경계 규칙 준수, 예외 불요.
- **`core/`에 두고 예외 문서화** — 기각. "도메인 인지는 이진 판정이라 추측이 사라진다"는 §1의 존재 이유를 첫 사례에서 깬다. 예외 하나가 다음 예외를 부른다.
- **`core/`에 무지 래퍼 + `shared/`에 도메인 Storage 2층 분해** — 기각. 135줄을 2층으로 쪼개는 건 §8 "사전 확장 금지"·"일회성 service = 과설계 신호" 위반.
- **`features/` 밖 최상위 예외 버킷** — 기각. 3버킷이 4버킷이 된다.

## Decision B — Dio·go_router·3버킷은 면제, Riverpod·freezed·Failure는 정합

mobile.md의 규칙 하나하나엔 근거가 붙어 있고, 그 근거들이 **feature N개·화면 N개·인증 있는 앱**을 전제한다. 냉파는 ADR로 화면 2개(0001)·단일 상태기계(0001)·서버 인증 없음(0005)을 의도적으로 고정한 측정 장치다 — 두 문서가 싸우는 게 아니라 적용 범위가 어긋난다. 축별로 순가치를 따진다.

| 축 | 판정 | 근거 |
| --- | --- | --- |
| Riverpod v3 | **정합** | 상태가 실제로 손으로 짜여 있다(ChangeNotifier 3개). 학습 가치 큼(ADR-0005) |
| freezed | **정합** | 모델이 수동 `copyWith`/`==`/`toJson`이다. 학습 가치 큼. 단 `AppEvent`는 마지막/면제(아래 Consequences) |
| Failure sealed | **정합** | Riverpod의 `AsyncValue.guard` 규약에 종속 — Riverpod과 한 덩어리 |
| Dio | **면제** | mobile.md 근거는 "단일 클라이언트에 **인증 토큰** 집중"인데 이 앱엔 인증 토큰이 없다(키는 서버리스, ADR-0005). 클라 1개·호출 3개 — 인터셉터가 집중할 대상이 없다. 순가치 음수 |
| go_router | **면제** | 화면 2개(ADR-0001 고정)·`Navigator.push` 1곳(`lib/ui/main_page.dart:64`). 순환·딥링크 문제 부재. `?debug` 쿼리 파라미터(ADR-0004 측정 푸터)를 깰 위험만 도입 |
| 3버킷 | **면제** | Decision A의 도미노(아래)로 feature가 사실상 `main` 1개 → "이름만 바뀐 layer-first". §1이 하이브리드를 정당화한 근거(Immich·AppFlowy)는 feature N개 전제 |

면제 3축은 "문제 없는 곳에 도구 끼우기"라 학습 가치(ADR-0005 회수 목표)도 낮다.

## Consequences

- **Decision A의 도미노** — `Storage`가 `shared/`에 있으면 그것이 만지는 모델도 `shared/` 이하여야 한다(`shared → features` import 금지). `storage.dart`가 `app_event`·`recipe`·`session_state`를, `llm_gateway.dart`가 `ingredient`·`recipe`·`suggestion`을 import하므로(실측) `lib/domain/` 10파일 전부가 `shared/models/`로 강제 이동한다. 그 결과 `features/`의 거주자는 사실상 `main` 1개다 — 이것이 Decision B의 3버킷 면제 근거다.
- **면제는 정합의 포기가 아니라 범위 재서명이다.** 파일럿 생존 후 새 코드가 계속 들어오면 두 관용구 공존이 길어지는 게 진짜 부채다. 면제 3축은 그 부채를 만들지 않는 축(호출 seam 1개·화면 2개·feature 1개)이라 공존 비용이 낮다.
- **안전망 전제 정정** — 리팩터의 안전망이라던 E2E는 144건이 아니라 30건이고, 그중 24건이 `MainController`(ChangeNotifier) 인스턴스를 직접 쥔다(`integration_test/core_loop_test.dart:44-68`). Riverpod 전환은 안전망을 같은 PR에서 재작성하므로, **안전망을 UI 관측(`find.byKey`)으로 디커플링하는 것이 Riverpod의 절대 선행**이다.
- **freezed 와이어 계약 — 지금이 무료 창, 단 `Recipe`는 라운드트립 호환 필수.** export JSON은 백업 #20의 와이어 계약이다. `AppEvent.parse`는 미지 유형을 nullable로 조용히 스킵하고 `Ingredient.toJson`은 조건부 필드를 생략한다 — json_serializable 기본 출력은 형태가 다르다. D0 전 초기화(#41)로 이벤트 JSON은 어차피 버려지므로 `AppEvent`·`Ingredient`의 toJson 형태 변경은 지금 안전하다. 단 **`Recipe`는 D0 초기화 때 `previewMerge`로 살아 넘어와야 하므로**(#41 절차) 백업 JSON 라운드트립 호환을 반드시 지킨다 — 골든 파일로 방어한다.
- **CI가 없다**(`.github/` 부재). 154+24 테스트를 흔드는 리팩터를 수동 게이트로 하는 건 도박이므로, 착수 전 경량 CI 배선이 사실상 선행이다.
- **착수 시점 — D0(2026-07-22) 전, 7/21까지.** 당초 "P2 킬 판정 후"로 적었으나 뒤집었다(2026-07-16 파운더 결정). 근거 — (1) 실사용 측정은 D0부터다. 7/16~7/21 배우자는 관통만 허용되고 실제 요리는 금지(ADR-0004)라 지금 코드를 바꿔도 오염시킬 측정이 없다. (2) 지금 앱 데이터는 D0 전 전부 초기화된다(#41) — freezed 와이어 계약을 바꿀 유일한 무료 창이다. (3) 베이스라인(7/21)이 배포보다 늦는 제약이라 7/21까지 재배포하면 D0는 안 밀린다. 실행 순서 위상정렬 — CI → 안전망 디커플링 → build_runner+Riverpod+riverpod_lint+Failure(한 덩어리) → freezed 점진 → 재배포·관통 재확인.
- mobile.md 원본(공용 `ai-rules`)은 수정하지 않는다 — Decision A/B는 냉파의 ADR 층위 결정이고, 규칙 리포를 갈라 다른 프로젝트에 파급시키지 않는다.
