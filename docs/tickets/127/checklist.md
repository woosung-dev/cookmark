# #127 체크리스트 — #121 컷오버 잔여 minor 묶음 (클라이언트 4건)

티켓 정본은 [#127](https://github.com/woosung-dev/cookmark/issues/127)이고, 인접 상류는 스펙 [#161](https://github.com/woosung-dev/cookmark/issues/161) §G(인지 경로)와 [#166](https://github.com/woosung-dev/cookmark/issues/166)(실패 문구 구분)이다. 결정 로그는 `context-notes.md`.

목표 한 줄 — **죽은 서버가 사용자 탓으로 읽히지 않고, 조용히 지나가지도 않는다. 그리고 결제된 원가는 저장이 실패해도 원장에 남는다.**

범위 경계 — **앱(`apps/mobile`)만.** 서버(`apps/api`) 0줄 · `contracts/` 0줄 · `tool/analyze_pilot.dart` 0줄.

## 파운더 확정 결정

- [x] **범위 = 클라이언트 4건, 동명 오연결(title→id)은 제외** — 매칭 계약에 식별자 왕복이 없어 6층 변경 + 프롬프트 행동 변경이고, flip 게이트([#170](https://github.com/woosung-dev/cookmark/issues/170)) 앞에 넣을 물건이 아니다. #127에 남기고 인계를 코멘트로 남긴다
- [x] **신고 유도 줄 = 저장 실패 카드 + 하이드레이트 실패 카드** — 이슈가 지정한 것은 앞의 하나지만, 죽은 서버에서 코호트가 **가장 먼저 보는 카드**는 뒤의 것이다
- [x] **거절 피드백은 `RecipeForm` 안 인라인 한 줄** — 두 화면이 폼을 공유하므로 배선 1곳으로 둘 다 고쳐지고, 거절 시 입력을 지우지 않아 사용자가 고칠 수 있다

## 산출물

- [x] **A. 502의 의미를 create로 좁혔다** — `_ensureStatus(..., {extractionFailedOn502})`, `create()`만 `true`. 서버 실측 근거: 502를 내는 recipes 라우트는 `POST /recipes` 하나뿐이고(`UpstreamLLMError`) bulk 실패는 500이다. 나머지 넷의 502는 인프라 502라 `unavailable`이다
- [x] **B. 신고 유도 줄 공유 위젯 신설** — `lib/ui/widgets/report_hint.dart`. 3표면(`FailureCard`·`RecipeAddFailureCard`·`_SyncErrorCard`)이 각자 키로 쓴다. 기존 `Key('failure-report-hint')`·문구는 무변경 — 리터럴 3복제로 문구가 갈리면 신고 경로가 갈린다
  - [x] `RecipeAddFailureCard`는 **kind로 가르지 않는다** — `RecipeApiFailureKind` 4종엔 사용자 입력이 원인인 값이 하나도 없다. 없는 갈림을 위해 `LlmFailureBlame` 같은 축을 새로 세우지 않았다
- [x] **C. 재추출 PATCH 실패의 원가·stage** — `AppEvent.errorShown`에 optional `usage` 추가(⑩ `recipeBookChanged`와 동일 관용구, **카탈로그 12종 무변경**), `_retryExtractionOnServer`가 `LlmUsage?`를 try 밖으로 호이스트, stage `'extraction'` → `'reextractSave'`
  - [x] `analyze_pilot`은 `costUsd`를 switch 밖에서 쓸어담으므로 **툴 0줄**로 원장에 합산된다 — 그 사실을 유닛으로 잠갔다
- [x] **D. 저장 거절 표면화** — `RecipeAddOutcome{accepted,duplicateUrl,incomplete,busy}` + `add()` 반환 + 폼의 `Key('recipe-add-rejection')` 한 줄. 폼의 자체 빈-값 조기 return은 제거해 판정을 컨트롤러 한 곳으로 모았다
  - [x] `busy`는 문구 없음 — 버튼의 "재료를 알아보는 중…"이 이미 그 말을 한다. **exhaustive switch가 트립와이어**다(값이 늘면 컴파일이 깨져 문구를 강제로 답하게 한다)
  - [x] 낡아진 주석 2곳 정정(`_addToServer`의 "폼은 이미 비워졌다" · `RecipeAddFailureCard.onRetry` doc)
- [ ] 동명 레시피 saved 제안 URL 오연결 — **하지 않았다.** 위 범위 결정 참조
- [ ] `_addToServer`의 `stage: 'extraction'` 오기 — **하지 않았다.** A와 같은 결이나 이슈가 열거하지 않았고 기존 테스트가 값을 잠그고 있다(`context-notes.md`에 표면화)

## 검증

- [x] 유닛 **516** green (신규 — 502 표 구동 5건 · 재추출 원가/stage 2건 · `add` 반환 5건 · 폼 거절 5건 · 실패 카드 5건 · 하이드레이트 카드 1건 · 원장 합산 1건)
- [x] E2E green — 신규 2건(core_loop "담기지 않은 이유" · api_cutover ⑱ 인프라 502). ⑱은 **실 `ServerRecipeRepository` + `MockClient`**로 돌린다: 질문이 "상태 코드로부터 무엇이 화면에 뜨는가"라 경계 페이크에 kind를 손으로 꽂으면 검증이 성립하지 않는다(#166 교훈)
- [x] **트립와이어 검증** — 신규 E2E 2건의 단언을 각각 틀린 값으로 바꿔 **실패하는 것을 확인**한 뒤 복원했다(`flutter drive`는 케이스별 출력이 없어 안 도는 E2E와 통과한 E2E가 같아 보인다)
- [x] `test/ui/failure_card_test.dart` **무변경 통과** — `ReportHint` 추출이 행동을 안 바꿨다는 증거
- [x] `dart format --set-exit-if-changed` · `flutter analyze --fatal-infos` green
- [x] `/code-review` — Standards·Spec 두 축
