# Context Notes — #142 LLM 경계 오형식 200 하드닝

자율결정 감사 추적. 티켓 [#142](https://github.com/woosung-dev/cookmark/issues/142) · 스펙 [#140](https://github.com/woosung-dev/cookmark/issues/140) · 지도 [#129](https://github.com/woosung-dev/cookmark/issues/129).

## 결함 재확인 (코드를 읽고 확인)

`ProxyLlmGateway._post`는 타임아웃·비200·`FormatException`만 정규화한다. **JSON으로는 파싱되는데 모양이 다른 200**은 세 메서드의 캐스트·널 체크에서 `TypeError`를 낳는다.

- 본문이 Map이 아님(`[]`·문자열) → `_post`의 `(jsonDecode(...) as Map)`
- `usage` 없음 → `body['usage']!`의 널 체크 연산자
- 항목 모양이 다름(`ingredients: ['대파']`) → `(item! as Map)`

`TypeError`는 `Error`이지 `Exception`이 아니다 — `on FormatException`도 `on Exception`도, 컨트롤러의 `on LlmFailure`도 못 잡는다. 그래서 `MainController._recognize`가 `_phase`를 `failed`로 못 넘기고 **`recognizing`에 영구 고착**한다. 마지막 `notifyListeners()`조차 실행되지 않는다.

## 결정 로그

### 1. 예외 유형 열거가 아니라 광범위 catch (AC 명시)

`on TypeError`만 잡으면 두더지잡기다 — 응답 모양이 조금 달라지면 `NoSuchMethodError`·`RangeError`가 대신 나오고 고착이 그대로 돌아온다. 리포가 이미 배운 교훈([#123](https://github.com/woosung-dev/cookmark/issues/123): "결정적 경로는 광범위 except로 최종단을 보장한다").

계약을 한 줄로 — **게이트웨이 밖으로 `LlmFailure` 아닌 것이 새지 않는다.**

### 2. 헬퍼를 `llm_gateway.dart`(seam 계약 파일)에 둔다

`normalizeLlmFailures`는 특정 구현의 사정이 아니라 **경계의 계약**이다. `LlmFailure` 정의 바로 옆에 두면 구현자가 계약과 강제 장치를 같이 본다. 구현마다 private 헬퍼를 복제하면 한쪽만 고쳐지는 게 이 결함의 재발 경로다.

`on LlmFailure { rethrow; }`가 먼저 온다 — `empty`·`lowQuality`는 이미 정규화된 도메인 실패라 `error`로 뭉개면 실패 카드 문구가 갈린다.

### 3. `ApiV1LlmGateway`도 같이 고친다 (티켓 범위 밖 — 표면화)

파일럿 빌드(`main.dart`)는 `ProxyLlmGateway`만 쓴다. `ApiV1LlmGateway`는 컷오버용([#121](https://github.com/woosung-dev/cookmark/issues/121))이라 D0와 무관하다.

그런데 거기 이미 있는 방어가 **정확히 AC가 금지한 `on TypeError` 열거**다. AC의 계약은 특정 구현이 아니라 seam의 성질이므로 두 구현이 갈리면 계약이 아니라 우연이 된다. 치환은 **코드를 줄인다**(try 블록 3개 → 래퍼). 되돌리기 쉬우니 포함했다 — 범위를 좁히려면 `api_v1_llm_gateway.dart` 한 파일만 revert하면 된다.

### 4. `main_controller.dart`는 건드리지 않는다

컨트롤러에 방어적 catch-all을 더할 수도 있었지만 하지 않았다.

1. **계약의 위치** — AC가 계약을 게이트웨이에 뒀다. 컨트롤러가 이중으로 잡으면 게이트웨이가 새도 테스트가 안 죽어서 계약이 조용히 썩는다.
2. **세션 격리** — [#143](https://github.com/woosung-dev/cookmark/issues/143)이 `main_controller`를 건드린다(스펙 #140 분해 시 "병렬 금지" 경고). 같은 파일을 안 건드리면 충돌 표면이 0이다.

### 5. E2E 범위 — 인식·매칭 (추출은 유닛)

AC는 "**코어 루프**를 돌리면"이라고 쓴다. 코어 루프는 사진→인식→체크리스트→매칭→제안이고, 추출은 레시피 북 표면이라 루프 밖이다. E2E가 인식·매칭 두 단계의 실패 카드를 고정하고, 세 호출 전부의 정규화는 유닛이 고정한다.

E2E가 페이크 게이트웨이가 아니라 **실 `ProxyLlmGateway` + `MockClient`(오형식 200)** 를 쓰는 게 핵심이다 — `FakeLlmGateway`는 `LlmFailure`를 얌전히 던지므로 이 결함을 재현조차 못 한다. 결함이 게이트웨이와 컨트롤러 **사이**에 있으니 그 사이를 실제로 통과시켜야 한다.

부수효과로 `pumpApp`의 인자 타입이 `FakeLlmGateway?` → `LlmGateway?`로 넓어졌다. 페이크 전용 필드(`recognizeCallCount` 등)를 쓰는 호출자는 자기 지역 변수로 접근하므로 무영향이다.

## 회귀 검증 (테스트가 실제로 결함을 잡는지 확인)

"고쳤다" 다음에 "테스트가 통과한다"만 확인하면, 그 테스트가 고치기 **전에도** 통과했을 가능성이 남는다 — 그러면 재발 방어가 0이다. 그래서 양방향으로 확인했다.

- **유닛** — 픽스 전 10건 실패(전부 `_TypeError` 이탈), 픽스 후 25/25 green.
- **E2E** — `normalizeLlmFailures`를 `return await interpret();`로 일시 무력화하고 재실행했다.
  - 인식 테스트 → `TypeError: Instance of 'JSArray<dynamic>'`로 실패
  - (첫 실패에서 러너가 중단되므로) 인식 테스트를 건너뛰고 재실행 → 매칭 테스트도 실패
  - 무력화를 되돌린 뒤 `scripts/e2e.sh` 전량(core_loop·api_cutover) green
- **트립와이어** — `test/architecture/llm_gateway_contract_test.dart`도 같은 방식으로 확인했다. `ApiV1LlmGateway.extractIngredients`의 래퍼를 일시로 벗기니 정확히 그 메서드를 지목하며 실패했다.

## 리뷰 반영 (2축 code-review)

- **계약이 관례로만 남는다는 지적(양 축 동시 지적)** — `normalizeLlmFailures`는 메서드마다 손으로 붙이는 opt-in이라, 네 번째 메서드나 세 번째 구현이 조용히 계약 밖으로 나갈 수 있었다. `test/architecture/llm_gateway_contract_test.dart` 트립와이어를 추가해 못박았다. 선례는 `navigation_test.dart`(go_router 면제)이고, 그 파일이 적은 이유("프로즈 예외만으로는 조용히 부패한다 — 이 리포가 겪은 실패다")가 여기 그대로 적용된다. 이 결함 자체가 arm #25 → #26으로 살아 넘어온 것이다.
- **sweep 테스트가 프록시만 훑는다** — `ApiV1LlmGateway`에도 같은 sweep을 추가했다.
- **매칭 E2E의 재시도가 존재만 확인됐다** — 재시도가 실제로 `/api/match`를 다시 부르는지(2회) 세도록 고쳤다. 버튼이 있기만 하고 아무것도 안 하면 사용자에겐 고착과 구별되지 않는다.
- **반영하지 않은 것** — `LlmFailure.detail`이 화면에 안 읽히니 `'응답 형식 불일치: $e'`의 보간이 무의미하다는 나머지 지적. 기존 `_post`도 `e.toString()`·`'HTTP ${statusCode}'`를 detail에 넣고 있어 그 관례를 따랐고, 파일럿 중 파운더가 콘솔에서 원인을 읽는 값이다.

## 남은 리스크 (이 티켓 밖 — 표면화)

- **E2E는 Web 타깃인데 파일럿은 네이티브 APK다.** dart2js와 Android VM이 같은 오형식 본문에 다른 throwable을 낼 수 있다. 수정이 유형 무관한 bare `catch`라 실질 위험은 낮지만, 화면 수준 증거가 웹에서만 나왔다는 건 사실이다. 네이티브 관통은 [#141](https://github.com/woosung-dev/cookmark/issues/141)·[#134](https://github.com/woosung-dev/cookmark/issues/134) 몫이다.
- **`MainController._recognize`의 성공 경로 잔여** — 게이트웨이 호출 뒤의 `appendEvent`·`_saveSession`이 같은 `try` 안에 있어서, 거기서 `LlmFailure` 아닌 것이 나면 마지막 `notifyListeners()`를 건너뛰어 **똑같은 고착 증상**이 난다. `Storage.appendEvent`가 이미 하드닝돼 있어(#137) 잠재적이고 라이브가 아니다. 그리고 그 파일은 [#143](https://github.com/woosung-dev/cookmark/issues/143)의 것이라 여기서 건드리지 않았다.

## 확인한 함정

- **`usage` 없음을 "정상"으로 바꾸지 않았다.** `ExtractionResult.usage`는 nullable이고 apps/api 경계는 JSON-LD 결정적 추출에서 null을 준다(#123). 하지만 **파일럿 프록시는 항상 LLM을 돌아 usage가 온다** — `ProxyLlmGateway`가 `body['usage']!`를 요구하는 건 의도된 것이다. 여기서 null 허용으로 완화하면 원가 원장에 구멍이 뚫린다(스펙 US 28). 목표는 고착 대신 **실패 카드**이지 관대해지는 게 아니다.
- **`catch (e)`는 `Error`도 잡는다** — Dart에서 `on Exception`은 못 잡지만 bare `catch`는 모든 throwable을 잡는다. 이 차이가 결함의 전부였다.
