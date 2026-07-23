# Flutter 네이티브 OIDC 로그인 도입 비용 — "진짜 로그인"이 선택지로 살아있으려면 알아야 하는 값

> wayfinder 리서치 티켓 [#155](https://github.com/woosung-dev/cookmark/issues/155) · 인증 화해 결정 [#156](https://github.com/woosung-dev/cookmark/issues/156) 대기 · WebSearch/WebFetch + 리포 1차 소스 조사
> 조회 시점: 2026-07-23
> 표기 — ✅ 1차 소스(pub.dev·공식 문서·리포 코드)로 확인 / ⚠️ 2차 소스(검색 요약) 교차확인
> **이 문서는 결정하지 않는다.** #156이 무인증 라우트·사전프로비저닝 토큰·진짜 로그인 세 옵션 중 하나를 파운더와 함께 고르는 자리이고, 여기서는 세 번째 옵션의 실제 값만 잰다.

## 0. 지금 서 있는 지점 (리포 1차 소스 확인 사항)

- **ADR-0005**(`docs/adr/0005-flutter-mvp-web-first.md`)는 "로그인·서버 DB 없음"을 명시하지만, 그 결정은 **Web 빌드 파일럿**을 전제로 한 2026-07-13 시점 판단이다. 이후 지도 #129(2026-07-19 CLOSED)가 파일럿을 네이티브 APK 단독으로 역전시켜 "설치 0" 전제가 이미 한 번 깨졌다 — 이 문서 §5는 그 위에서 "로그인 1회"의 한계비용을 잰다.
- **서버(`.claude/rules/backend.md` §9·§12, 티켓 #100)는 이미 구현돼 있고 배포만 안 됐다.** `apps/api/src/auth/`에 카카오·구글 OIDC 코드 플로우(authlib) + 자체 세션 테이블 + `iss`+`sub` 전용 계정이 전량 존재한다(✅, 코드 확인).
  - `GET /auth/{provider}/login` — IdP 인가 화면으로 302 (`apps/api/src/auth/router.py:47`).
  - `GET /auth/{provider}/callback` — authlib이 코드 교환·ID 토큰 검증을 마치고, **JSON 바디로 `SessionResponse`(토큰 포함)를 직접 반환하면서 동시에 쿠키를 세팅**한다(`router.py:59-80`). 네이티브로 이 토큰을 돌려주는 딥링크 리다이렉트는 **아직 없다** — §2에서 이게 왜 중요한지 다룬다.
  - state·nonce는 `SessionMiddleware`(서명 쿠키, `apps/api/src/main.py`)가 로그인 시작→콜백 사이를 나른다 — 이건 "브라우저가 그 사이 쿠키를 들고 있어야 성립"하는 설계라, **시스템 브라우저/Custom Tab 안에서는 동작하지만 앱 WebView를 거치면 깨질 수 있다**.
- **앱(`apps/mobile/`)에는 로그인 UI가 전혀 없다.** 현재 두 실행 경로 모두 로그인을 우회한다.
  - `main.dart`(파일럿 배포 arm) — `ProxyLlmGateway`, Vercel 서버리스 함수를 **무인증**으로 호출(지도 #129 결정 #130).
  - `main_api_cutover.dart` — `apps/api`를 쓰지만 세션 토큰을 **빌드타임에 굽는다**: `--dart-define=COOKMARK_SESSION_TOKEN=<scripts/seed_sessions.py 토큰>` (✅, `apps/mobile/lib/main_api_cutover.dart:6-7`, `apps/mobile/lib/llm/api_v1_llm_gateway.dart:173`). `apps/api/scripts/seed_sessions.py`가 서버 DB에 계정·세션을 직접 심어 발급한 토큰을 그대로 앱에 박아 넣는 "사전프로비저닝 토큰" 방식 — 로그인 화면·IdP 왕복이 앱에 존재하지 않는다.
  - `pubspec.yaml`에는 OAuth·시큐어스토리지 관련 패키지가 **하나도 없다**(✅, 확인) — `http`·`image_picker`·`shared_preferences`(평문 로컬 저장, Keystore 아님)·`url_launcher`뿐.

이 세 가지 위에서 "진짜 로그인"을 붙이는 비용을 잰다.

## 1. Flutter 네이티브 Android에서 카카오·구글 OIDC 코드 플로우 — 표준 경로 (Q1)

아래 패키지 상태를 확인했다(전부 2026-07-23 pub.dev, ✅).

| 패키지 | 최신 버전 | 최근 publish | 용도 |
| --- | --- | --- | --- |
| [`flutter_appauth`](https://pub.dev/packages/flutter_appauth) | 12.0.2 | 26일 전 | 범용 OIDC/OAuth 코드 플로우(AppAuth Android/iOS 공식 바인딩, PKCE 지원), 430 likes·322k 다운로드 — 활발히 유지보수 |
| [`app_links`](https://pub.dev/packages/app_links) | 최신 | — | 커스텀 스킴/딥링크 수신(설계 (b)에서 서버 콜백이 앱으로 돌아올 때 필요) |
| [`kakao_flutter_sdk_user`](https://pub.dev/packages/kakao_flutter_sdk_user) | 2.0.0+1 | 3개월 전 | 카카오 공식 Flutter SDK, verified publisher(developers.kakao.com) |
| [`google_sign_in`](https://pub.dev/packages/google_sign_in) | 7.2.0 | 10개월 전 | 구글 공식(flutter.dev 퍼블리셔), Credential Manager 기반 |
| [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) | 10.3.1 | 56일 전 | Android Keystore(AES-GCM+RSA-OAEP)·iOS Keychain — §9가 요구하는 "보안 저장소"의 실제 구현체. **현재 프로젝트에 미도입** |

**표준 경로는 provider별로 실제로 갈라진다.**

- **범용 경로 — `flutter_appauth`**: AppAuth(RFC 8252 계열 "외부 유저 에이전트" 패턴 — Custom Tab/시스템 브라우저를 열고 커스텀 스킴으로 앱에 돌아옴, WebView 금지가 사실상 표준)를 그대로 씀. Android 리다이렉트 스킴은 `build.gradle.kts`의 `manifestPlaceholders["appAuthRedirectScheme"]`로 주입하거나 `AndroidManifest.xml`에 `RedirectUriReceiverActivity` intent-filter를 직접 추가한다(✅, pub.dev README). 스킴은 **소문자 고정**이 필수. 카카오도 `kauth.kakao.com`이 표준 OIDC discovery(`/.well-known/openid-configuration`)를 노출하므로(§9 `oidc.py`가 이미 이걸로 서버 쪽을 구현했다) `flutter_appauth`로 직접 붙일 수 있다.
- **카카오 전용 — `kakao_flutter_sdk_user`**: `loginWithKakaoTalk()`/`loginWithKakaoAccount()`가 **인가 코드→토큰 교환까지 앱에서 직접 끝낸다**(✅, developers.kakao.com/docs/ko/kakaologin/flutter). 카카오톡 앱이 깔려 있으면 웹뷰 없이 앱 전환만으로 로그인 — UX는 최상이지만, §9가 요구하는 "서버가 코드 교환"과 **아키텍처가 반대 방향**이다(아래 §2).
- **구글 전용 — `google_sign_in`**: Credential Manager 기반. Google 공식 문서(2026-05-26 최종 갱신, ⚠️)는 네이티브 앱에 대해 "Google Identity Services Android 라이브러리"를 권장하며, OOB 플로우는 2023-01-31부로 전 클라이언트 타입에서 폐지됐다(⚠️). 범용 `flutter_appauth`로 구글도 붙일 수 있지만, Google이 실제로 미는 노선은 이쪽이 아니라 전용 SDK다.

**결론** — "패키지가 뭐냐"는 질문에는 표준 답이 하나가 아니다. `flutter_appauth` 하나로 두 provider를 통일하면 서버(§9)와 대칭적인 아키텍처(모든 OIDC 왕복이 한 곳)를 유지할 수 있지만 카카오톡 앱 전환 같은 provider별 네이티브 UX를 포기한다. 전용 SDK(카카오/구글 각각)를 쓰면 UX는 낫지만 provider마다 완전히 다른 코드 경로가 생기고, 카카오 SDK는 §9가 정한 "서버가 코드 교환" 원칙과 정면으로 어긋난다.

## 2. 서버 접합 — 설계 (a) vs (b) (Q2)

### 설계 (a) — 앱이 IdP와 직접 코드 플로우

`flutter_appauth`의 `authorize()`(주의: `authorizeAndExchangeCode()`가 아니다 — 이건 앱이 code exchange까지 끝내버려 client_secret 없는 public client 취급이 되므로 §9의 "서버가 코드 교환" 전제와 어긋난다)를 호출해 **인가 코드 + PKCE code_verifier + nonce만** 앱이 받고, 이를 서버 새 엔드포인트(POST)로 전달한다. 서버가 code→token 교환과 ID 토큰 검증을 대신 수행 후 세션 발급.

- **서버 쪽 재사용 불가 지점** — 현재 `oidc.fetch_identity()`는 authlib의 `client.authorize_access_token(request)`에 `Request` 객체 통째(쿼리 파라미터의 `code`+`state`, 세션 쿠키의 nonce)를 넘기는 고수준 헬퍼다(`apps/api/src/auth/oidc.py:102-119`). 설계 (a)는 이 헬퍼가 전제하는 "브라우저가 콜백으로 GET 요청을 보낸다"는 흐름 자체가 없다 — 앱이 POST로 code만 보내므로, authlib의 저수준 API(`client.fetch_access_token()` 계열)로 code→token 교환·ID 토큰 서명 검증·nonce 대조를 **손으로 다시 짜야 한다**. §9 인용문에 있는 카카오 fail-open 함정(`SCOPE = "openid"` 상수, `oidc.py:16-19` 주석)도 이 새 경로에서 **똑같이 재현해야** 한다 — 지금은 서버 한 곳에만 있는 방어가 새 코드 경로에도 복제된다는 뜻.

### 설계 (b) — 서버가 코드 플로우, 앱은 브라우저만 띄운다

앱이 `url_launcher`(externalApplication 모드, Custom Tab)로 `{API_BASE}/auth/{provider}/login`을 시스템 브라우저에서 연다. 서버가 IdP로 302 → IdP 로그인 → 서버 콜백으로 302. 이 전체 구간은 **하나의 시스템 브라우저 세션 안에서** 일어나므로 `SessionMiddleware`의 state·nonce 서명 쿠키가 그대로 유지된다 — Custom Tab은 앱 WebView가 아니라 OS의 실제 브라우저 프로세스를 재사용하는 구조라 쿠키 저장소가 그 브라우저의 것이다. 이게 §9가 전제하는 "서버가 코드 플로우를 한다"의 네이티브 버전이고, 이미 구현된 authlib 경로를 **그대로 재사용**한다.

- **딥링크 회수가 실제로 필요한 지점** — 지금 `auth_callback`은 JSON을 반환한다. 시스템 브라우저가 그 JSON 페이지에 도달해도 **앱은 아무것도 못 받는다** — 브라우저와 앱은 별개 프로세스다. 네이티브가 토큰을 받으려면 콜백이 **커스텀 스킴으로 302**해야 한다(예: `cookmark://auth-callback?token=...&expires_at=...`). 앱은 `app_links`로 그 스킴의 intent-filter를 등록해 받는다. 이건 **서버 쪽 신규 코드**다 — router.py의 `auth_callback`에 플랫폼 분기(예: 로그인 시작 시 `state`에 클라이언트 redirect target을 실어 콜백에서 그대로 꺼내 쓰거나, `?platform=native` 쿼리로 분기)를 추가해야 하고, **오픈 리다이렉터가 되지 않도록 커스텀 스킴 화이트리스트 검증**이 필요하다.

### 비교

| | (a) 앱이 직접 | (b) 서버가 코드 플로우 |
| --- | --- | --- |
| §9 원칙과의 정합 | 어긋남 — "provider ID 토큰은 서버가 1회 검증"이 아니라 앱이 먼저 받는다 | 그대로 부합 |
| authlib 재사용 | 안 됨 — 저수준 API로 재구현 | 됨 — `oidc.py` 무변경 |
| 카카오 fail-open 방어 위치 | 서버+클라이언트 양쪽에 각각 필요 | 서버 한 곳(이미 존재) |
| 신규 서버 코드 | code exchange 라우트 신규 작성 | 콜백에 리다이렉트 분기 + redirect_uri 화이트리스트 |
| 신규 앱 코드 | `flutter_appauth` PKCE 흐름 + POST | `url_launcher` + `app_links` 딥링크 수신 |
| UX | 앱 안에서 완결(Custom Tab 왕복 없음 가능성) | 반드시 외부 브라우저로 나갔다 돌아옴 |

**§9는 명시적으로 (b)를 전제한다** ("IdP의 OIDC 코드 플로우로 로그인하고, provider의 ID 토큰은 로그인 순간 1회 검증 후 폐기" — 주어가 서버다). 이 리서치의 결론은 (b)가 서버 쪽 재작업을 최소화하고 §9의 카카오 함정 방어를 한 곳에 유지하지만, **"딥링크로 토큰을 회수한다"는 부분은 지금 코드에 없고 새로 만들어야 한다** — "서버는 이미 다 됐다"는 인상과 달리 네이티브 접합점 자체는 미구현이다.

## 3. 구현 표면 추정 (Q3) — 정직한 범위, 실측 스파이크 없음

아래는 **문서 조사 기반 추정이지 실측이 아니다.** §9 자체가 서버 세션 표면을 "~30-50줄"로 못박은 것과 같은 정신으로, 정밀 스토리포인트가 아니라 자릿수 감각만 제공한다. 설계 (b) 기준.

**서버 쪽 (#100 위에 추가, `apps/api`)**

- `auth_callback`에 네이티브 분기 + 커스텀 스킴 리다이렉트 + redirect_uri 화이트리스트 검증 — 대략 30~60줄 + 교차 검증 테스트(오픈 리다이렉터 방지).
- `Settings`에 허용 커스텀 스킴 목록 추가(§9.1의 CORS 허용 목록과 같은 패턴).
- 카카오·구글 개발자 콘솔에 커스텀 스킴 redirect_uri 등록 — 코드 아닌 사람 작업, 각 provider 콘솔 왕복.
- **총 서버 쪽 반나절~1일**(구현+로컬 검증). #100이 이미 계정·세션·CORS·§12 최소식별자를 다 갖췄으므로 이 추정은 좁다.

**앱 쪽 (`apps/mobile`)**

- 신규 의존성 — `app_links`(딥링크 수신) + `flutter_secure_storage`(Keystore, **현재 미도입**). `mobile.md` §0 스캐폴드 절차대로 `pub add` 필요.
- `AndroidManifest.xml` — 커스텀 스킴 intent-filter 추가 + **`taskAffinity=""` 재검토(§4 함정 참조, 필수)**.
- 로그인 버튼 UI + 로그인 진행중/에러 상태 — ADR-0001(화면 전환 없는 단일 세로 페이지)과 결합해야 하므로 새 화면이 아니라 기존 단일 페이지 상태 기계에 상태를 추가해야 한다(mobile.md AGENTS.md 인용 — "코어 루프는 화면 전환 없이 섹션 확장/접힘").
- 로그인 성공 시 토큰을 `flutter_secure_storage`에 저장, 기존 `ApiV1LlmGateway`/`ServerRecipeRepository`가 생성자로 받는 `sessionToken`을 dart-define 상수 대신 저장소 읽기로 배선 변경(`apps/mobile/lib/llm/api_v1_llm_gateway.dart`·`apps/mobile/lib/data/server_recipe_repository.dart` 양쪽).
- 로그아웃 UI(서버 `POST /auth/logout` 호출 + 로컬 secure storage 삭제, §4 함정 참조).
- 딥링크 레이스 처리 — 콜드 스타트(앱이 꺼진 채 딥링크로 기동) vs 이미 실행 중(포그라운드로 딥링크 수신) 두 경로를 다 받아야 함.
- **견적 — 단일 provider 기준 2~4일 실작업**(설계+구현+실기기 검증, 콘솔 설정 왕복 포함). **카카오+구글 둘 다면 가산이 아니라 거의 배**(provider마다 콘솔 등록·리다이렉트 URI·엣지케이스가 독립적이라) — **4~7일 범위**로 보는 게 정직하다. 이 프로젝트가 파일럿용 n=2 단일 블라인드(ADR-0004)임을 감안하면 provider 선택 자체도 #156에서 좁힐 여지가 있다(예: 배우자 둘 다 카카오만 쓴다면 1개로 충분).

## 4. 함정 (Q4)

- **카카오 authlib fail-open (§9가 지목한 것)** — scope에 리터럴 `openid`가 없으면 authlib이 nonce를 저장하지 않고, nonce가 없으면 ID 토큰 검증을 통째로 건너뛴다. 카카오는 콘솔 토글만 켜져 있으면 scope 무관하게 `id_token`을 준다. `oidc.py:16-19`가 `SCOPE = "openid"` 상수로 이미 막아뒀다(✅, 코드 확인). **설계 (b)를 쓰면 이 방어가 서버 한 곳에만 있으면 충분**하다 — 이게 (a) 대신 (b)를 미는 이유 중 하나다. (a)를 택하면 앱 쪽 `flutter_appauth` scope 설정에도 `openid`가 빠지지 않도록 별도로 챙겨야 하고, 놓쳐도 에러 없이 조용히 미검증 토큰이 오간다(§9 원문 그대로).
- **리다이렉트 스킴 충돌 — 이 리포에 이미 존재하는 구체적 함정** — `apps/mobile/android/app/src/main/AndroidManifest.xml`의 `MainActivity`에 `android:taskAffinity=""`가 이미 박혀 있다(Flutter 기본 스캐폴드의 StrandHogg 완화, #141 계보와 무관하게 `flutter create` 기본값). `flutter_appauth` 공식 README와 커뮤니티 이슈(⚠️, `MaikuB/flutter_appauth` 저장소)가 정확히 이 설정을 "리다이렉트가 앱으로 안 돌아오는" 원인으로 지목한다 — 빈 `taskAffinity`가 인증 브라우저→앱 복귀를 별도 태스크로 튕겨낸다. 완화책은 minSdk 30 이상이면 그냥 제거, 미만이면 패키지명(`dev.woosung.cookmark`)과 다른 커스텀 문자열로 대체다. **이 리포는 `minSdk`를 Flutter 툴체인 기본값 그대로 쓰고(`flutter.minSdkVersion`, 명시적 override 없음, ✅ `build.gradle.kts` 확인) 실측 없이는 30 이상인지 단정할 수 없다** — #141 계보의 교훈("실측이 예측 반증")과 같은 패턴으로, 문서만 보고 넘어가면 D-day에 로그인 브라우저가 앱으로 안 돌아오는 채로 파운더가 그걸 목격하게 된다.
- **토큰 폐기·로그아웃** — 서버는 이미 멱등이다(`logout`이 세션 행을 삭제, 이미 죽은 토큰으로 불러도 결과 같음, §9 인용). 네이티브에서 빠지기 쉬운 건 **로컬 secure storage 삭제를 잊는 것** — 서버는 401을 주는데 앱은 캐시된 토큰을 계속 `Authorization` 헤더에 실어 보내면, mobile.md §4의 "재시도 정책을 정의 안 하면 에러 UI 대신 무한 로딩이 기본 동작"과 결합해 로그아웃 후에도 조용히 재시도 루프에 빠질 수 있다. IdP 쪽 연결 해제(카카오 unlink)는 §12.3이 이미 "안 한다"고 명시적으로 못박았다(액세스 토큰을 보관해야 하는데 이는 §12.1 최소식별자·§9 "ID 토큰 1회 검증 후 폐기" 둘 다와 충돌) — 이 결정은 로그인 도입 여부와 무관하게 그대로 유지된다.
- **애플 로그인 트리거** — §9가 명시: "iOS 네이티브 출시 시 의무"(App Store 심사 4.8), authlib provider 추가는 ~10줄+라우트로 작지만 **애플 client secret이 ES256 JWT**라는 특이점이 있다. 냉파는 현재 **Android 전용 파일럿**(지도 #129 결정, iOS 미계획)이라 지금 당장 트리거되지 않는다. 다만 "카카오+구글만" 결정을 지금 내리면, 미래 iOS 출시 시점에 이 트리거가 걸려 애플 로그인을 추가 재작업으로 얹어야 한다 — #156이 이 사실을 알고 결정하는 것과 모르고 결정하는 것은 다르다.
- **단일 페이지 구조와의 결합** — `apps/mobile`은 go_router가 아직 없고(`mobile.md` 목표 구조 대비 부채, AGENTS.md 명시) 딥링크 수신 진입점이 `main.dart` 하나뿐이다. `app_links`로 받은 URI를 어디서 파싱해 단일 페이지 상태 기계에 꽂을지가 배선 신규 항목이다 — 기존 라우팅 인프라를 재사용할 수 없다.

## 5. ADR-0005 "설치 0 · 마찰 0" 전제가 실제로 얼마나 깎이나 (Q5)

이 질문은 이미 한 번 답이 갱신된 전제 위에서 물어야 한다 — 지도 #129(2026-07-19 CLOSED)가 "파일럿 전 역전·웹 폴백 없음"으로 **"설치 0"을 이미 깨뜨렸다.** 현재 온보딩 모델(메모 #135 계보)은 "설치·레시피 import 둘 다 파운더 hands-on" — 배우자는 사이드로드 Play Protect 경고를 보고, 파운더가 옆에서 설치를 도와주는 **대면 세션**이다. "로그인 1회"의 비용은 이 맥락 안에서 재야 한다.

- **상대적으로는 저렴하다** — 이미 "설치+권한 허용"이라는 더 무거운 마찰을 통과한 세션에 얹는 한계 비용이다. 카카오톡이 폰에 깔려 있으면 카카오 로그인은 앱 전환 1~2탭으로 거의 마찰이 없고, 구글은 기기에 이미 계정이 로그인돼 있을 가능성이 높아 계정 선택 1탭에 그칠 수 있다. 파운더가 옆에서 "이거 눌러줘" 한 마디로 해결되는 수준이라는 뜻이다.
- **절대적으로는 0이 아니다.**
  - 계정이 기기에 안 붙어 있으면 비밀번호 입력이 추가된다 — 파일럿 표본(배우자)의 실제 기기 상태를 확인 안 하면 이 비용을 과소평가하게 된다.
  - Custom Tab이 열렸다 앱으로 돌아오는 전환은 ADR-0004(단일 블라인드 파일럿)의 계측 순도에 **개입 로그를 하나 더 남긴다.** #133 계보의 "오염 세그먼트" 관례처럼, 로그인 이벤트도 별도 세그먼트로 분리해야 P2 킬 기준(자발적 재방문·수동 수정 계측)이 로그인 마찰과 뒤섞이지 않는다.
  - n=2라는 표본 규모에서 "로그인 버튼이 있다"는 사실 자체가 **"회원가입하는 앱"이라는 프라이밍**이 될 수 있다 — "그냥 사진 찍어보는 앱"이라는 애초 가설 검증 의도와 사용자 기대가 어긋날 위험이다. 이건 정량화 불가능한 추정이고, 파운더가 판단할 몫이다.
  - **재설치·핫픽스 시나리오(#133 "열린 핫픽스" posture)에서 마찰이 반복될 수 있다.** 사전프로비저닝 토큰(현재 방식)은 재설치해도 토큰이 빌드에 박혀 있어 마찰이 0이다. 진짜 로그인은 로컬 secure storage가 지워지는 재설치마다(또는 세션 만료 30일 후) 다시 로그인해야 한다 — n=2 파일럿 기간(D0 전후 며칠~몇 주) 안에서는 이 반복이 실제로 발생할 가능성은 낮지만, 0은 아니다.

**정직한 프레이밍** — "0 마찰"에서 "대면 온보딩 세션에 흡수 가능한 1회성 저마찰 단계"로 이동한다. 온보딩이 파운더 hands-on 대면 세션 안에 있는 한 이 비용은 작다. 그 전제가 깨지는 시나리오(원격 재설치·핫픽스 재배포)에서는 비용이 커진다.

## 이 사실이 결정에 어떻게 쓰이나

#156은 세 옵션을 놓고 화해해야 한다 — **무인증 라우트**(현재 파일럿 arm, `main.dart`/`ProxyLlmGateway`, 지도 #129 결정 #130), **사전프로비저닝 토큰**(현재 컷오버 트랙, `main_api_cutover.dart`, `seed_sessions.py`로 서버가 미리 발급한 토큰을 빌드에 굽는 방식), **진짜 로그인**(이 문서). 이 문서가 보태는 값은 다음과 같다.

- **비용 축** — 무인증 라우트는 서버·앱 양쪽 다 추가 코드 0(이미 그렇게 돌아간다). 사전프로비저닝 토큰은 이미 구현·검증 완료(#100·`main_api_cutover.dart` 존재)이고 파운더의 수동 개입(토큰 재발급·재배포)만 재설치마다 든다. 진짜 로그인은 §3 추정대로 **서버 반나절~1일 + 앱 4~7일**(provider 2개 기준)이 새로 든다 — n=2 파일럿의 남은 일정에서 이게 감당 가능한 크기인지가 #156의 1차 판단 재료다.
- **§9 표준 정합 축** — §9(자체 OIDC 세션)는 처음부터 "진짜 로그인"을 겨냥해 쓰인 표준이다. 사전프로비저닝 토큰은 §9의 세션 운반·저장 규격(Keystore+Bearer)을 흉내만 내고 실제 로그인 UX가 없는 **중간 상태**다 — §9를 "완성"하는 유일한 옵션이 진짜 로그인이라는 뜻이지, 그게 파일럿에 필요하다는 뜻은 아니다.
- **계측 순도 축(ADR-0004)** — 무인증·사전프로비저닝 두 옵션은 로그인이라는 개입 자체가 없어 계측이 가장 깨끗하다. 진짜 로그인은 §5가 정리한 "개입 로그 1건 추가"를 대가로 치른다.
- **미래 부채 축** — 진짜 로그인을 지금 안 붙이면 §9 표준과 앱 코드 사이의 간극(현재 부채, AGENTS.md가 이미 "기존 코드 관용구는 선례가 아니라 부채"라 명시)이 유지된다. 붙이면 그 간극은 메워지지만, 애플 로그인 트리거(§4)처럼 새 미래 부채가 생긴다.

어느 축에 얼마의 가중치를 둘지는 파운더와 #156이 정한다.

## 소스

**리포 1차 소스**
- `.claude/rules/backend.md` §9·§12
- `docs/adr/0005-flutter-mvp-web-first.md`
- `apps/api/src/auth/{router,oidc,service,dependencies,schemas}.py`
- `apps/api/src/main.py`, `apps/api/src/core/config.py`
- `apps/mobile/lib/llm/api_v1_llm_gateway.dart`, `apps/mobile/lib/data/server_recipe_repository.dart`, `apps/mobile/lib/main_api_cutover.dart`
- `apps/mobile/android/app/src/main/AndroidManifest.xml`, `apps/mobile/pubspec.yaml`, `apps/mobile/android/app/build.gradle.kts`

**외부 1차/공식 소스**
- [flutter_appauth — pub.dev](https://pub.dev/packages/flutter_appauth)
- [app_links — pub.dev](https://pub.dev/packages/app_links)
- [kakao_flutter_sdk_user — pub.dev](https://pub.dev/packages/kakao_flutter_sdk_user)
- [google_sign_in — pub.dev](https://pub.dev/packages/google_sign_in)
- [flutter_secure_storage — pub.dev](https://pub.dev/packages/flutter_secure_storage)
- [카카오 로그인 — Flutter 가이드, Kakao Developers](https://developers.kakao.com/docs/ko/kakaologin/flutter)
- [OAuth 2.0 for iOS & Desktop Apps — Google Identity](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Use Code Model — Google Identity](https://developers.google.com/identity/oauth2/web/guides/use-code-model)
- [Authorize access to Google user data — Android Developers](https://developer.android.com/identity/authorization)
- [MaikuB/flutter_appauth (GitHub, taskAffinity 이슈 계보)](https://github.com/MaikuB/flutter_appauth)
