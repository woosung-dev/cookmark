# Context Notes — #146 운영 문서 네이티브 치환

자율결정 감사 추적. 티켓 [#146](https://github.com/woosung-dev/cookmark/issues/146) · 스펙 [#140](https://github.com/woosung-dev/cookmark/issues/140) ④ · 지도 [#129](https://github.com/woosung-dev/cookmark/issues/129) · 온보딩 정본 [#135](https://github.com/woosung-dev/cookmark/issues/135) resolution · 핫픽스 [#133](https://github.com/woosung-dev/cookmark/issues/133) · 단일맹검 ADR-0004.

이 티켓은 **순수 문서**다 — 코드 0줄. 하지만 문서가 서술하는 대상(네이티브 초기화 메커니즘·숨은 제스처·오형식 200 하드닝)은 이미 랜딩된 코드다. 그래서 "코드를 읽고 서술이 코드와 맞는지 확인"이 이 티켓의 검증 앵커다(테스트 아님).

## 코드로 확인한 사실 (문서 서술의 정본)

### 초기화 메커니즘 — 롱프레스 제스처 → 초기화 버튼 → 확인 다이얼로그

- **트리거** — `main_page.dart`의 앱바 타이틀 `GestureDetector(onLongPress: _controller.toggleDebugFooter)`. 같은 롱프레스가 토글로 도로 닫는다. `excludeFromSemantics: true`(접근성 트리 누출 차단, #143). 매 실행 기본 숨김.
- **초기화 버튼** — `debug_footer.dart`의 "기록 초기화" 버튼(`Key('reset-record')`) → 부모 `main_page.dart`의 `_confirmResetPilotRecord()`가 `AlertDialog`("기록을 초기화할까요?" / "이벤트 기록과 진행 중인 재료 목록이 지워져요. 레시피 북은 그대로 남아요." / 취소·초기화) → `초기화` 확정 시 `resetPilotRecord()`.
- **보존 경계** — `storage.dart` `clearPilotRecord()`는 `events`·`session`·`lastBackupAt`·`expectationNoteSeen`를 지우고 `recipes`는 보존(#144). 레시피 북은 그대로 남는다.

### "이벤트 0이 정상"의 코드 정본 — `_recordEpoch`

`main_controller.dart`의 `resetPilotRecord()`가 `_recordEpoch++`를 올리고, `_appendUnlessReset(epoch, …)`이 시작 시점 epoch가 아직 살아 있을 때만 이벤트를 남긴다. 초기화는 그 호출이 속한 구간 자체를 지우므로, 뒤늦게 돌아온 인식·매칭 응답의 이벤트도 버려진다. 코드 주석이 그대로 `AC("초기화 후 정상 상태 = 이벤트 0")`이라고 못박는다. **웹은 재import가 backup 이벤트 1건을 남겨 "이벤트 1"이 정상이었지만, 네이티브엔 재import 자체가 없어 "이벤트 0"이 정상이다.** 이 반전이 티켓이 "가장 조용히 위험한 항목"으로 지목한 그것.

### 오형식 200 하드닝(#142) — 스모크가 검증할 대상

`llm_gateway.dart`의 `normalizeLlmFailures`가 `catch (e)`(bare — Error·TypeError까지)로 오형식 200을 `LlmFailure(LlmFailureKind.error, …)`로 정규화한다. 그래서 사용자는 영구 로딩 대신 재시도 가능한 실패 카드를 본다. #65 ① 스모크가 이걸 확인한다(#133이 지명한 완화 검증점).

## 결정 로그

### 1. `?debug` 5곳은 서술을 지우지 않고 현재 트리거로 치환한다

`d0-readiness.md`의 10·12·16·27·33행이 `?debug`를 가리킨다(#143 커밋 `f90e902`가 코드에서 제거). #145의 "서술 자체는 지우지 않는다" 관례를 따르되, 여기 5곳은 **시점 기록이 아니라 파운더가 D0에 실제로 밟을 절차**라 반드시 현재 동작으로 갱신한다. ADR-0007의 `?debug` 언급은 시점 기록이므로 그대로 둔다(티켓 코멘트 지시).

### 2. ADR-0011은 아직 리포에 없다 — 계획 식별자로 참조한다 (경계 이슈)

#9 AC는 정정 코멘트가 "#135 resolution · ADR-0011"을 가리키라고 한다. 그런데 ADR-0011은 **형제 티켓 #145**가 만든다(현재 OPEN·ready-for-agent). 스펙 #140 ④가 번호를 "ADR-0011"로 고정하므로 계획 식별자로 참조하되 "(#145에서 기록)"를 병기해 정직하게 표시한다. #146의 다른 산출물은 ADR-0011 존재에 의존하지 않는다(확인함).

### 3. #9는 본문 무편집 + 정정 코멘트 — closed 이슈의 시점 정본 보존

#9는 CLOSED이고 resolution 코멘트가 2026-07-13 시점의 규약 정본이다. 본문/resolution을 고치면 그 시점 기록이 소실된다. AC대로 **정정 코멘트**를 덧붙여 네이티브 치환분으로 포인터만 건다.

### 4. #41·#65 본문은 편집한다 — OPEN 실행 티켓이라 시점 기록이 아니라 살아 있는 절차

#41·#65는 OPEN이고 파운더가 D0에 따라갈 실행 절차다. #9(closed·시점 정본)와 달리 본문을 직접 재작성해야 현재 절차를 말한다. AC가 "재작성"·"치환"을 명시.

### 5. 배우자 기기 "다시 롱프레스로 닫기" 한 줄을 넣는다 (#146 코멘트)

푸터는 프로세스가 죽을 때까지 열려 있고 `AppLifecycleState.resumed` 자동 닫기는 의도적으로 미채택(안드로이드 알림 하나 내렸다 올려도 발화 → 파운더가 읽는 도중 닫힘). 파운더는 배우자 기기에서 푸터를 여므로, 폰을 돌려주기 전 "확인 후 다시 롱프레스로 닫는다"가 없으면 계측이 열린 채 남아 ADR-0004 오염.

## 범위 밖 (경계 — 재결정 안 함)

- ADR-0011 신규 + `AGENTS.md`·`docs/coding-standards.md`·`CONTEXT.md` = **#145**(형제).
- export/JSON 전송·초기화·debug 트리거 등가물 = #136(이미 랜딩: #143·#144).
- 핫픽스 재설치 데이터 보존 = #132·#133(같은 키스토어=업데이트).
