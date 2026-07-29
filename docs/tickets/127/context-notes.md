# #127 결정 로그 — 컷오버 잔여 minor 묶음

## 착수 시점의 정정 — 이슈가 센 5건은 실제로 4건이다

[#168](https://github.com/woosung-dev/cookmark/issues/168)이 "LLM seam 401이 일반 error로 뭉개짐"을 이미 해소했다. `sendWithDeviceSession`이 401을 **전송 초크에서 흡수**해 재등록 후 1회 재전송하므로 `LlmFailureKind`에 `unauthorized`가 생기지 않았고, 재등록마저 실패해 `error`로 접히는 것은 **서버 도달 실패가 맞아** #166의 문구가 그대로 성립한다. 이슈 코멘트가 이미 적어둔 사실이고, 코드로 재확인했다.

## 범위에서 뺀 것 — 동명 오연결(title→id)

이슈가 *"서버 UUID 왕복이 있으니 title 대신 id 기반으로"*라고 적었다. **그 전제가 매칭 경로에선 거짓이다.**

- 요청 `MatchRecipe` = `title` + `ingredients` (`apps/api/src/llm/schemas.py`, 주석이 명시적으로 *"URL은 클라이언트에 남는다"*)
- 응답 `Suggestion` = `menu`·`source`·`missing`·`reason`·`match_score` — **식별자 없음**
- 프롬프트(`src/common/prompts.py`)가 `menu는 저장된 제목 그대로`를 **규칙으로 못박고** 있고, 저장 레시피 블록도 `- {title}: {ingredients}` 형태다

UUID가 왕복하는 곳은 `/api/v1/recipes` CRUD이지 `/api/v1/llm/match`가 아니다. 그래서 id 기반으로 바꾸려면 앱 모델·앱 요청/파싱·`ProxyLlmGateway`·서버 요청/응답 스키마·seam 후보 모델·`build_match_response`·**프롬프트**·`contracts/openapi.yaml` 재생성·schemathesis·양쪽 테스트까지 6층이 움직인다. 핵심은 마지막이 아니라 **프롬프트다** — LLM에 식별자를 되받게 하는 것은 타입 변경이 아니라 행동 변경이라 eval이 따라야 한다.

두 가지를 다음 사람에게 남긴다.

1. **`Recipe.id`는 nullable이 설계다**(로컬 모드·미이전 항목은 null). id **대신** title이 아니라 id **에 title 폴백**이어야 한다. 아니면 하이드레이트 가드(#165)가 지킨 미이전 항목이 조용히 매칭에서 빠진다.
2. **원 UUID를 되받게 하지 말 것.** 환각·절단된 UUID는 조회에 실패하고, 실패하면 현행 강등 규칙(`saved` → `generated`)이 발화해 **이 티켓이 고치려던 바로 그 증상**이 다른 트리거로 재현된다. 프롬프트에 인덱스(`0`·`1`·`2`)를 주고 서버가 UUID로 되매핑하는 편이 구조적으로 안전하다.

flip 게이트([#170](https://github.com/woosung-dev/cookmark/issues/170))가 되돌릴 수 없는 선이고, 프롬프트 행동 변경을 그 후보 빌드에 싣지 않는 것이 이번 범위 결정의 근거다.

## A — 502를 플래그로 갈랐다(매퍼 복제도, 신규 kind도 아니다)

세 안을 놓고 골랐다.

- **메서드별 매퍼 복제** — 기각. 401·404·파싱 정규화가 다섯 벌로 늘어난다.
- **`RecipeApiFailureKind`에 `infraUnavailable` 신설** — 기각. `unavailable`이 이미 그 뜻이고, #166이 세운 *"분류는 이미 있었고 문구만 배신하고 있었다"*를 다시 어긴다.
- **채택: `_ensureStatus(..., {extractionFailedOn502})`** — 상태→의미 매핑이 **엔드포인트에 종속된다는 사실 자체**를 호출부에 명시한다. 기본값이 `false`라 새 메서드가 늘어도 안전한 쪽으로 떨어진다.

서버 근거는 실측이다 — `apps/api/src/recipes/router.py`에서 502는 `create_recipe`의 `UpstreamLLMError` 하나뿐이고, `apps/api/src/migration/router.py`의 가져오기 실패는 **500**이다.

## B — 신고 줄에 분류 축을 새로 만들지 않았다

`FailureCard`는 `LlmFailureBlame.isServerSide`로 가른다. 같은 모양을 `RecipeApiFailureKind`에도 만들 뻔했으나 **가를 것이 없다** — 4종 중 사용자 입력이 원인인 값이 하나도 없고, 502조차 추출 사다리가 앞단을 전부 제목 추론으로 강등한 뒤 **LLM 자체가 죽었을 때만** 난다. 없는 갈림을 위해 축을 세우면 다음 사람이 그 축을 진짜라고 믿는다. 그래서 무조건 붙이고, **왜 안 갈랐는지**를 위젯 주석에 남겼다.

문구를 `ReportHint` 위젯으로 뽑은 이유는 DRY가 아니라 **갈라짐의 대가**다. 이 한 줄이 코호트 장애에서 파운더에게 닿는 유일한 경로라(스펙 #161 §G) 표면마다 다른 말을 하면 신고가 새는 곳이 생긴다. 판정은 뽑지 않았다 — 두 경계의 판정 기준이 실제로 다르기 때문이다.

## C — `errorShown`을 넓혔지 새 이벤트를 만들지 않았다

카탈로그 12종은 `analyze_pilot_test`(툴↔enum)와 `core_loop_test`(enum↔실제 방출)에 **이중으로 잠겨** 있다. 새 유형을 만들면 두 잠금을 동시에 풀어야 하고 수집된 백업 JSON의 해석도 갈린다. `usage`는 유형이 아니라 ⑫의 **데이터 필드**라 잠금 무영향이다 — ⑩ `recipeBookChanged`가 이미 optional usage를 같은 방식으로 싣는다.

`analyze_pilot`이 **툴 변경 0줄**로 이 원가를 먹는 이유는 `costUsd` 합산이 `switch` **밖**에 있어 이벤트 유형과 무관하게 쓸어담기 때문이다. 그건 우연히 성립하는 성질이라 유닛으로 잠갔다(`원가 원장 — 실패한 호출도 결제됐으면 센다`).

`stage`는 enum이 아닌 자유 문자열이고 `analyze_pilot`은 **읽지 않는다**(집계는 `kind`로 한다). 그래서 `'reextractSave'` 추가는 툴·잠금 영향이 0이고, 값의 효용은 export JSON을 사람이 읽을 때의 정직함뿐이다 — 그거면 충분하다(필드 이름이 거짓말하지 않는 것이 목적이었다).

## D — 반환값을 골랐고, 그 대가로 필드 비우기가 늦어진다

두 설계를 놓고 골랐다.

- **컨트롤러 상태 + 폼에 prop 전달**(`addFailure`와 같은 모양) — 배선이 화면 2곳이고, 빈-값 판정은 여전히 폼이 해야 해서 **판정이 두 곳으로 갈린다**.
- **채택: `add()`가 `RecipeAddOutcome`을 반환** — 배선이 폼 1곳이고 화면 코드 변경은 타입뿐이다. 판정도 컨트롤러 한 곳으로 모인다.

**의도한 행동 변경 1건** — 예전엔 제출 즉시 필드를 비웠고, 지금은 `accepted`가 돌아온 뒤에 비운다. 거절 세 갈래는 첫 `await` 전에 결정되므로 **마이크로태스크 안에서** 돌아온다(프레임 전이라 깜빡임이 없다). 저장이 실제로 도는 동안에는 폼이 잠긴 채 입력이 보이는데, 이쪽이 정직하고 저장이 실패해도 입력이 사라지지 않는다. `failedAdd`는 그대로 뒀다 — 실패 카드의 "다시 시도"는 폼의 현재 입력과 무관하게 성립해야 한다.

## 표면화(고치지 않음)

- **`_addToServer`의 `stage: 'extraction'`** (`recipe_book_controller.dart`) — kind와 무관하게 그 값을 적는다. 502면 맞지만 `unavailable`·`unauthorized`는 아니다. C와 같은 결이나 **이슈가 열거하지 않았고** `recipe_book_server_test.dart`가 값을 잠그고 있어 별도 판단이 필요하다.
- **`stage`에 잠금이 없다** — 살아 있는 값이 이제 6종(`recognition`·`matching`·`extraction`·`hydrate`·`remove`·`reextractSave`)인데 `hydrate`·`remove`·`reextractSave`엔 카탈로그도 enum도 없다. 잠글지 여부는 별건이다.
- **하이드레이트 실패는 이벤트를 남기지 않는다** — E2E ⑱을 쓰다 발견했다. 실패 카드가 화면에 뜨는데 `errorShown`이 안 남아 export만 보는 분석에서는 그 장애가 보이지 않는다(`emptyServerBook` 가드 경로만 이벤트를 남긴다). 범위 밖이라 단언을 걷어냈다.

## 함정

- **`ReportHint` 추출의 증거는 기존 테스트가 무변경으로 통과하는 것**이다. `failure_card_test.dart`는 문구와 키를 하드코딩하고 있어(구현의 분류 함수를 부르지 않는다) 그대로 회귀 가드가 된다.
- **`flutter drive`는 첫 실패에서 런 전체를 중단한다** — 트립와이어를 두 파일에 동시에 심으면 뒤 파일이 안 돈다. 하나씩 심고 확인했다.
- **chromedriver 심링크가 또 끊겨 있었다**(brew Caskroom엔 151만, Chrome은 150.0.7871.187). 이전 세션 스크래치패드의 150.0.7871.187 바이너리를 `PATH` 앞에 얹어 해결. 병렬 워크트리와 겹치지 않게 `CHROMEDRIVER_PORT=4477`.
