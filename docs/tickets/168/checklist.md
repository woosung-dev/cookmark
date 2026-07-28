# #168 체크리스트 — 앱 기기 세션 경계 (부팅 등록 · 401 재등록 · 로그인 화면 0)

티켓 정본은 [#168](https://github.com/woosung-dev/cookmark/issues/168), 상류는 스펙 [#161](https://github.com/woosung-dev/cookmark/issues/161) §D·Testing Decisions(지도 [#153](https://github.com/woosung-dev/cookmark/issues/153) CLOSED)이고 결정 정본은 [ADR-0012](../../adr/0012-anonymous-device-registration.md). 결정 로그는 `context-notes.md`.

목표 한 줄 — **토큰 없이 부팅해도 로그인 화면 0으로 코어 루프가 `apps/api`를 관통한다. 세션이 죽어도(401) 재등록으로 이어지고 로컬 레시피가 살아남는다.**

범위 경계 — 앱(`apps/mobile`) + 내가 낡게 만든 문서. **서버(`apps/api`) 0줄**([#167](https://github.com/woosung-dev/cookmark/issues/167)이 이미 냈다)이고 **신규 seam 1개**(기기 세션 경계)다.

## 파운더 확정 결정

- [x] **등록 토큰 백킹 = `flutter_secure_storage`** — 읽기/쓰기 경계는 `data/storage.dart`가 계속 쥔다(`TokenStore` 인터페이스를 그 뒤에 둔다)
- [x] **401 복구는 전송 초크에** — 실 HTTP 경계 안, 공유 헬퍼 1개. **`LlmFailureKind` 신규 값 0**
- [x] **`COOKMARK_SESSION_TOKEN` 완전 제거** — 인증 모드를 하나로 남긴다

## 산출물

- [x] **신규 seam 1개** — `lib/auth/device_session.dart`(인터페이스 · `DeviceSessionFailure` · `normalizeDeviceSessionFailures` · `sendWithDeviceSession`) + `api_v1_device_session.dart`(실 HTTP) + `fake_device_session.dart`(페이크). **LLM seam은 1개 그대로**다
- [x] **정책 지점 1곳** — `sendWithDeviceSession`이 토큰을 싣고 401이면 재등록 후 **딱 1회** 재전송한다. 호출 지점은 `ApiV1LlmGateway._post`·`ServerRecipeRepository._send` 둘뿐이고, 둘 다 이미 모든 요청을 한 메서드로 모으고 있어 접합이 각각 한 블록이다
- [x] **401이 경계 실패 타입에 닿기 전에 흡수된다** — `LlmFailureKind`·`RecipeApiFailureKind` **무변경**. 재등록마저 실패하면 각 경계가 기존 값(`error` / `unauthorized`)으로 접어 #166 실패 문구가 그대로 맞는다
- [x] **등록 토큰이 단일 스토리지 모듈을 통과한다** — `Storage.readDeviceToken()`/`writeDeviceToken()`. 위젯·게이트웨이는 보안 저장소를 모른다. 갈아끼우는 경로는 **패키지가 제공하는 플랫폼 스왑**(`FlutterSecureStorage.setMockInitialValues({})`)이다 — `SharedPreferencesAsyncPlatform.instance`를 갈아끼우는 기존 13개 테스트 파일의 관용구와 동형이라 **갈아끼우기용 인터페이스를 따로 만들지 않았다**(`mobile.md` §2-1·§8). 토큰 read만 **async**다(보안 저장소라 동기 캐시가 성립하지 않고, `Storage.open()`에 크립토 왕복을 붙이지 않기 위해서다 — E2E 이벤트 대기 헬퍼가 폴링마다 `open()`을 부른다)
- [x] **기록 초기화가 토큰을 보존한다** — `clearPilotRecord()`가 `_preservedOnReset`과 같은 자리에서 명시 결정으로 적고, `clear()`(테스트 전용)는 토큰까지 지운다
- [x] **동시 등록 합류** — 부팅에서 둘이 같은 프레임에 물어도 등록 왕복은 1회다. `reregister(usedToken)`은 다른 경계가 이미 갈아끼웠으면 등록하지 않는다 — **고아 계정을 안 만든다**(파기가 파운더 수동이라, ADR-0012)
- [x] **엔트리 2개 배선** — 컷오버·스파이크가 `COOKMARK_REGISTER_KEY`를 읽어 `ApiV1DeviceSession`을 조립한다. **등록을 `runApp` 앞에서 await하지 않는다**(부팅을 막지 않는다)
- [x] **`main.dart` 0줄 변경** — 파일럿 핫픽스 경로 보존(ADR-0004). 폴백 분기(`_serverBase.isEmpty` → 프록시)도 동작 무변경
- [x] **트립와이어 3건** — ① `COOKMARK_REGISTER_KEY` 읽기 지점을 엔트리 2개로 고정 ② **`COOKMARK_SESSION_TOKEN` 읽는 파일 0개** 고정 ③ 경계 계약 테스트를 표 구동으로 바꿔 신규 경계를 **편입**(`lib/auth`의 `implements DeviceSession` + `http.Client` 구현이 `normalizeDeviceSessionFailures`를 통과해야 한다)
- [ ] 로그인 화면·탭·설정 항목 — **만들지 않았다**(ADR-0012). 승격 트리거 4건 중 하나가 발화하면 그때
- [ ] 신규 `AppEventType` — **만들지 않았다**. 카탈로그 12종은 `core_loop_test`와 `analyze_pilot_test`에 이중으로 잠겨 있고, 재등록은 뒤이은 빈 목록이 발화시키는 기존 `errorShown(kind:'emptyServerBook')`로 export에 남는다

## 검증

- [x] `dart format --output=none --set-exit-if-changed lib/ test/ integration_test/ test_driver/` — 통과
- [x] `flutter analyze --fatal-infos` — No issues found
- [x] `flutter test` — **490 passed**(기존 438 + 신규 52). 신규 파일 `test/auth/api_v1_device_session_test.dart` 14건
- [x] `bash scripts/e2e.sh` — **컷오버 17건(15 + 신규 2) · 코어 루프 38건 전량 green**
- [x] **웹 타깃 실측 — 착수 전 리스크가 닫혔다.** E2E ⑯이 기기 세션 경계를 **실 구현**으로 태워 `Storage.writeDeviceToken()` → 재개봉 `readDeviceToken()`을 Web 타깃에서 관통시킨다. 즉 `flutter_secure_storage_web`의 **암복호 경로가 실제로 돈다**.
  - ⚠️ **첫 근거는 틀렸었고 코드리뷰가 잡았다.** 처음엔 "E2E `setUp`의 `storage.clear()`가 토큰 삭제까지 태우니 웹 경로가 산다"라고 적었는데, `flutter_secure_storage_web`의 `delete()`는 `localStorage.removeItem` 한 줄이라 **`crypto.subtle`을 안 탄다**(`flutter_secure_storage_web-2.1.1/lib/flutter_secure_storage_web.dart`). 삭제가 통과해도 쓰기가 산다는 증거가 되지 못한다 — 그래서 쓰기·읽기를 직접 태우도록 ⑯을 고쳤다
- [x] `flutter build apk --debug -t lib/main_api_cutover.dart` — 네이티브 플러그인 접합 확인(Gradle assembleDebug 성공)
- [x] `flutter build web --no-tree-shake-icons` — 웹 산출물 생존(E2E 게이트의 전제)
- [x] **트립와이어가 실물임을 증명** — `normalizeDeviceSessionFailures`를 일부러 떼고 계약 테스트가 잡는 것을 확인 후 복원
- [x] **신규 E2E 2건이 진짜 도는지 증명** — `registerCount` 단언을 일부러 틀린 값으로 바꿔 두 테스트가 각각 실패하는 것을 확인 후 복원(`flutter drive`는 케이스별 출력이 없어 조용히 안 도는 위험이 있다)
- [x] `/code-review` — Standards·Spec 두 축. **반영 5건 · 표면화 3건**
  - **반영 ① (두 축 합의, 유일한 실동작 결함)** — `DeviceSessionFailure`를 `RecipeApiFailureKind.unauthorized`로 접고 있었다. 그 한 값은 403뿐 아니라 **네트워크·타임아웃·형식 불일치**까지 덮는데, `unauthorized` 문구("접속 정보가 유효하지 않아요")는 서버에 못 닿은 것을 자격증명 문제로 오인시킨다 — 스펙 §G·#166이 가르라고 한 두 가지를 도로 뭉치는 셈이다. **`unavailable`로 바꿨다.** 진짜 401(재등록한 토큰으로도 거부)은 `_ensureStatus`가 여전히 `unauthorized`로 낸다. LLM 경계는 원래부터 `error`(서버 귀책 버킷)라 이제 둘이 같은 판단을 한다
  - **반영 ② (Spec 축, 내 검증이 거짓이었다)** — 위 웹 타깃 항목. E2E ⑯을 실 `ApiV1DeviceSession`으로 바꿔 쓰기·읽기를 관통시켰다
  - **반영 ③ (Standards 축)** — `TokenStore`/`SecureTokenStore`/`MemoryTokenStore` **파일째 삭제**. `mobile.md` §2-1이 *"테스트도, 병렬 계약 고정도 abstract의 사유가 아니다"*라 못박고 §8 트리거는 "출시되는 둘째 구현"인데 인메모리 구현은 `test/` 전용이었다. 패키지가 `FlutterSecureStorage.setMockInitialValues({})`를 제공하고 그게 리포의 기존 플랫폼 스왑 관용구와 동형이라 인터페이스가 통째로 불필요했다. **부수 이득 — 페이크가 운영 계약을 재구현하던 Duplicated Code도 함께 사라졌다**
  - **반영 ④ (Spec 축)** — `AGENTS.md`의 `lib/` 레이아웃 열거에 `auth/`가 빠져 있었다(내가 만든 드리프트). 추가
  - **반영 ⑤ (Standards 축)** — `Storage.clearPilotRecord` 주석이 *"새 키가 생기면 지워지는 쪽이 기본값"*이라 적는데 보안 저장소 쪽은 손대지 않아 기본값이 **반대**다. 그 반전과 재검토 트리거(둘째 값이 생길 때)를 주석에 명시. `pubspec.yaml`의 신규 의존성 역할 주석도 추가
- [x] 커밋

## 표면화 — 고치지 않은 것

- **`mobile.md` §0 네트워크(Dio + `core/network/`) 이탈 — 리팩터 트랙([#38](https://github.com/woosung-dev/cookmark/issues/38)) 항목으로 등재 권고.** 신규 경계가 자기 `http.Client`를 만들고 `sendWithDeviceSession`이 Bearer 부착 + 401 재전송을 손으로 짠다 — §0이 "단일 클라이언트에 인증 토큰·로깅 집중"이라 부른 인터셉터의 정의 그 자체다. coding-standards가 *"새 코드는 `mobile.md`를 따른다"*고 못박으므로 **이탈이 맞다.** 지금 고치지 않은 이유는 이 티켓만 Dio로 가면 `http`와 **네트워킹 스택이 둘**이 되기 때문이다 — `mobile.md` §8이 OpenAPI codegen에 대해 *"Dio 수기 호출과 병존 금지(이중 API 계층)"*라 적은 것과 같은 병이다. 전환은 세 경계를 함께 옮기는 일이라 #38의 몫이다.
- **신규 최상위 버킷 `lib/auth/` — 3버킷 미정합의 상속이 아니라 새 선택이다.** `mobile.md` §1 판정 규칙(도메인을 아는가)으로는 `DeviceSession`이 `core/`다. 현 레이아웃에 `core/`가 아예 없어 한 파일을 위해 절반만 이주시키는 대신 기존 형제 버킷(`llm/`·`data/`·`image/`·`platform/`)의 관례를 따랐다. **#38이 3버킷으로 옮길 때 함께 판정할 항목**이고, 그때 단일 스토리지 모듈·LLM seam의 미결(AGENTS.md)과 같은 자리에서 결정된다.
- **`_registering` 합류와 `reregister(usedToken)`는 책임 ③("401을 만나면 재등록한다")보다 넓다** — Spec 축이 minor scope creep으로 짚었다. 남긴 이유는 둘 다 **고아 계정을 만드는 경로를 닫기** 때문이고, ADR-0012가 고아 파기를 파운더 수동으로 못박아 안 만드는 쪽이 싸다. 합계 ~8줄이다.

- **`test/support/fake_server_recipe_repository.dart`와 `integration_test`의 인라인 사본이 여전히 둘이다.** 웹 타깃의 컴파일 루트 제약(`integration_test/`가 `../test/`를 import 못 한다)이 원인이고 이 티켓이 만든 것이 아니다. `FakeDeviceSession`은 같은 함정을 피하려고 처음부터 `lib/auth/`에 뒀다(`FakeLlmGateway` 선례).
- **`apps/api/scripts/seed_sessions.py`는 그대로 둔다.** 앱이 안 쓸 뿐 서버 개발·curl 스모크에서는 여전히 유효한 발급 경로다. `docs/pilot/api-cutover-smoke.md`의 curl 구간은 계속 그 토큰을 쓴다 — 다만 브라우저 구간이 이제 **다른 계정**(앱이 스스로 등록한)을 쓴다는 사실을 그 문서에 명시했다.
- **`reregister`의 잔여 경쟁 하나** — 두 경계가 **순차로** 같은 죽은 토큰에 401을 받고 그 사이 등록이 이미 끝났으면 두 번째는 새 토큰을 재사용한다(`usedToken` 비교). 하지만 두 경계가 서로 다른 죽은 토큰을 들고 있는 세계는 만들지 않았다 — 토큰의 정본이 세션 객체 하나라서 그럴 수 없다.
- **`expires_at`·`account`를 읽지 않는다.** 슬라이딩 갱신이 만료를 계속 밀어 발급 시점 값이 곧 낡고(#167 인계), 계정 식별자는 앱이 쓸 화면이 없다. 만료의 신호는 401 하나다.
- **`COOKMARK_REGISTER_KEY`가 비면 빈 Bearer로 등록 요청이 나간다** — 서버가 403을 내고 인라인 실패 카드로 뜬다. 클라이언트에서 미리 막지 않은 것은 의도다: 서버의 공백 거부 가드(#167)가 이미 정본이고, 앱이 따로 판정하면 규칙이 두 곳에 산다.
- **`.env.local`(gitignored)은 이 티켓 전에도 `COOKMARK_REGISTER_KEY`가 없으면 로컬 서버가 안 떴다**(#167). 값이 개발자별이라 리포가 정할 수 없고, 절차 정본은 `docs/pilot/api-cutover-smoke.md` §1·§2다.
