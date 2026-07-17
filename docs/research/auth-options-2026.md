# 인증 옵션 2026 현황 — Clerk×Flutter Web×FastAPI vs 대안

> wayfinder 티켓 [#89](https://github.com/woosung-dev/cookmark/issues/89) · WebSearch/WebFetch + pub.dev API + GitHub 1차 소스 조사 · 2026-07-17
> 표기 — ✅ 1차 소스로 확인 / ⚠️ 2차 소스 교차확인 또는 미검증
> 컨텍스트 — 1기 범위는 로그인 + 서버 레시피 북(#75), 스택은 FastAPI · Cloud Run 서울 · Neon 싱가포르 · Vercel rewrite same-origin `/api/v1`(#76). 원 요구는 `idea.md` "인증 : 카카오·구글 소셜 로그인". `.claude/rules/backend.md` §9는 Clerk JWT를 명시하나 **Clerk는 전제가 아니다**(2026-07-17 사용자 지시) — 이 문서는 [#77](https://github.com/woosung-dev/cookmark/issues/77)(인증 표준 그릴링)의 결정 입력이며, 최종 결정은 #77 몫이다.

## 핵심 결론

1. **Clerk × Flutter Web은 2026-07 현재 성립하지 않는다.** `clerk_flutter`는 0.0.17-beta(2026-07-16)이고 pub.dev 플랫폼 태그에 **web이 없다**(✅ pub.dev API — `android`·`ios`·`macos`뿐). README는 "**This SDK is community-maintained and provided as-is — not officially supported by Clerk**"라고 명시한다(✅) — 2026-07-15 커뮤니티 이관 커밋([#433](https://github.com/clerk/clerk-sdk-flutter/issues/433))으로 공식 SDK 지위가 철회됐고, Clerk 공식 문서 퀵스타트 목록에도 Flutter가 없다(✅). Web 지원은 오픈 이슈 [#237](https://github.com/clerk/clerk-sdk-flutter/issues/237)·오픈 PR [#362](https://github.com/clerk/clerk-sdk-flutter/issues/362)로 진행 중이며, 0.0.16-beta 웹 빌드는 스텁 3개(PasskeyAuthenticator·localStorage Persistor·allowed_origins 우회)를 손으로 꽂아야 겨우 돌고 **Sign out이 동작하지 않는다**([#427](https://github.com/clerk/clerk-sdk-flutter/issues/427), open)(✅).
2. **backend.md §9의 서버측 경로 자체는 건재하다** — `clerk-backend-api` 6.0.1(PyPI, Clerk 공식)의 `authenticate_request`가 networkless JWT 검증을 제공한다(✅). 끊긴 고리는 클라이언트(Flutter Web) 쪽이다. 즉 §9는 틀린 표준이 아니라 **"Flutter Web 클라이언트" 전제에서 1기에 적용 불가한 표준**이다 — 냉파가 §9와 갈라지면 편차를 ADR-0009에 명시해야 한다(#76이 이미 §9를 #77에 위임).
3. **카카오 지원 경로가 옵션을 가른다.** 네이티브 provider — **Supabase**(공식 가이드 + Flutter `signInWithOAuth(OAuthProvider.kakao)` 예제 ✅) · **Logto**(social connector ✅). 비네이티브 — **Clerk**(공식 docs 리포 social-connections 디렉토리에 kakao.mdx 부재 ✅, custom OIDC provider 경로만) · **Firebase**(OIDC 커스텀 provider는 **Identity Platform 업그레이드 필수 + 무료 50 MAU 한정** ✅ — 공식 가격 페이지 "SAML/OIDC: No-cost up to 50 MAUs").
4. **카카오는 표준 OIDC IdP다** — `https://kauth.kakao.com/.well-known/openid-configuration`이 표준 discovery 문서를 라이브로 반환한다(✅ 직접 fetch). 따라서 자체 JWT(authlib)에서 구글과 동일한 OIDC 코드 플로우로 처리된다. 단 `token_endpoint_auth_methods_supported`가 `["client_secret_post"]`뿐이라(✅) `client_secret_basic`을 기본값으로 쓰는 커스텀 OIDC 통합(Clerk·Firebase)에선 마찰 위험이 있다(⚠️ 실통합 미검증). authlib은 파라미터 하나로 해결된다.
5. **카카오 공식 Flutter SDK는 web 미지원이다** — `kakao_flutter_sdk_user` 2.0.0(developers.kakao.com verified publisher)의 플랫폼 태그는 `android`·`ios`뿐(✅ pub.dev API). 클라이언트 SDK 의존 경로는 Flutter Web에서 전부 막히고, **서버측 리다이렉트 플로우**(자체 JWT — SDK 불필요)나 **web 지원 SDK**(`supabase_flutter`·`firebase_auth`)만 성립한다.
6. **무료 티어는 전 옵션이 1기 규모를 넉넉히 감당한다** — Clerk 50k MRU(2026-02 상향 ✅) · Firebase 50k MAU(단 OIDC provider는 50 ✅) · Supabase 50k MAU(✅) · Logto 50k MAU + 소셜 커넥터 3개(✅). 결정 변수는 요금이 아니라 **카카오 경로 · Flutter Web 성숙도 · 운영 마찰**이다.
7. **공통 카카오 제약** — 이메일을 필수 동의항목으로 받으려면 비즈 앱 전환이 필요하다(⚠️ 카카오 데브톡·공식 문서 교차확인, 개인 개발자도 신청 가능). 1기는 OIDC `sub`(회원번호)로 레시피 북 소유자 식별이 성립하므로 이메일 없이 시작할 수 있다 — 어느 옵션을 골라도 동일한 제약이다.

## 옵션별 상세

### Clerk (`clerk_flutter` + `clerk_backend_api`)

- **Flutter Web 궁합** — 사실상 없음. 0.0.17-beta, web 플랫폼 태그 부재(✅), 커뮤니티 이관(✅), 웹 빌드는 수동 스텁 + Sign out 불능([#427](https://github.com/clerk/clerk-sdk-flutter/issues/427) open)(✅). 리포 스타 58개 — 성숙도 신호도 약하다.
- **FastAPI 검증 경로** — `clerk-backend-api` 6.0.1 `authenticate_request`(networkless, JWKS 기반)(✅). 이 구간만은 backend.md §9 그대로 성립한다. 세션 토큰은 ~60초 JWT로 클라이언트가 투명 갱신한다(#427 재현 보고에서 웹에서도 이 구간은 동작 확인).
- **무료 티어** — 50,000 MRU + 소셜 커넥션 3개(✅ 공식 가격 페이지). Pro $25/월부터 소셜 무제한.
- **카카오 경로** — 네이티브 provider 아님(✅ 공식 docs 리포 확인, Line은 있고 카카오·네이버는 없음). custom OIDC provider(social connection)로 붙일 수는 있으나 문서에 요금제 제한 명시가 없고(⚠️) `client_secret_post` 마찰 위험(⚠️ 미검증).
- **판정** — 조직·B2B SSO·멀티테넌트가 주력인 제품인데 정작 1기가 필요로 하는 Flutter Web 클라이언트가 없다. **backend.md §9는 Next.js류 웹 스택을 전제한 표준으로 읽어야 하며, 냉파 1기 적용은 불가.**

### Firebase Auth (`firebase_auth`)

- **Flutter Web 궁합** — 성숙. firebase.google.com verified publisher, 6.5.6, web 태그(✅), Flutter Favorite·4.28k likes. 웹은 JS SDK 위임으로 `signInWithPopup`/`signInWithRedirect` 지원(✅).
- **FastAPI 검증 경로** — `firebase-admin`의 `verify_id_token` 또는 서드파티 JWT 라이브러리 + Google 공개키(문서화된 수동 검증 경로)(✅). 성숙.
- **무료 티어** — 50k MAU(✅). **단 OIDC 커스텀 provider는 Identity Platform 업그레이드(Blaze) 필수 + 무료 50 MAU 한정**(✅), 초과분 과금(⚠️ 단가는 GCIP 가격 페이지 확인 필요).
- **카카오 경로** — 네이티브 아님(공식 federated 목록: Google·Apple·Microsoft·Twitter·GitHub·Yahoo 등)(✅). 경로 ① OIDC 커스텀 — 위 요금 조건 + Flutter에서 커스텀 OIDC `signInWithProvider` 이슈 보고([flutterfire #11591](https://github.com/firebase/flutterfire/issues/11591))(⚠️). 경로 ② custom token — 서버가 카카오 OAuth를 직접 수행 후 Firebase 커스텀 토큰 발급(한국 커뮤니티 통용 패턴) — **카카오 플로우를 어차피 서버에 직접 짜야 하므로 Firebase가 주는 가치가 반감**된다.
- **판정** — 구글 로그인만 보면 최강이지만, 핵심 판별자인 카카오에서 요금 조건(50 MAU)이나 이중 구현(custom token) 중 하나를 강요당한다. GCP 정렬(#76)이라는 가산점은 있다.

### Supabase Auth (`supabase_flutter`)

- **Flutter Web 궁합** — 성숙. supabase.io verified publisher, 2.16.0(9일 전), 전 플랫폼 web 포함(✅), 973 likes. 공식 카카오 가이드에 Flutter 예제가 있고 웹 분기(`kIsWeb`)까지 문서화(✅). 세션은 localStorage 보관 — HttpOnly 쿠키 대비 XSS 표면은 감수점.
- **FastAPI 검증 경로** — 표준 JWKS. `https://<project>.supabase.co/auth/v1/.well-known/jwks.json` + 비대칭 키(RS256/ES256)가 공식 권장이고 레거시 HS256 shared secret은 "strongly recommend against"(✅). PyJWT/jose 수십 줄 — Supabase SDK 없이 검증 가능.
- **무료 티어** — 50k MAU, 활성 프로젝트 2개, **무활동 1주 후 프로젝트 일시정지**(✅). Auth 전용이라도 정지되면 로그인이 죽는다 — 1기 저트래픽에서 실질 위험이며 주기적 ping 또는 Pro $25/월로 우회.
- **카카오 경로** — **네이티브 provider**(✅ 공식 문서 "Login with Kakao"). 구글도 네이티브. `client_secret_post` 등 카카오 특이사항을 Supabase가 이미 흡수했다.
- **운영 마찰(냉파 특유)** — **DB는 Neon이다**(#76 무편차 결정). Supabase를 Auth 전용으로 쓰면 ① 유저 레코드는 Supabase Postgres `auth` 스키마, 레시피 북은 Neon — 관리형 Postgres 2개 운영, FK 불가, `user_id`는 문자열 참조만. ② Supabase의 주력 가치(RLS·DB 통합)를 전부 버리는 비정형 사용. ③ 벤더 콘솔 +1.
- **판정** — 1기 표면(카카오+구글+JWT 검증)을 가장 적은 코드로 정확히 덮는다. 대가는 벤더 추가·정지 정책·DB 이중화라는 구조적 어색함.

### 자체 JWT — FastAPI 발급 (authlib)

- **Flutter Web 궁합** — 클라이언트 SDK가 아예 필요 없다. 서버측 리다이렉트 플로우(`/api/v1/auth/kakao/login` → kauth 리다이렉트 → callback → 세션 발급)라 카카오 SDK web 미지원 문제 자체가 소멸한다. **#76의 same-origin `/api/v1` rewrite 위에서 HttpOnly 쿠키 세션이 서드파티 쿠키 문제 없이 자연스럽게 성립** — 스택 결정과 정합이 좋다.
- **FastAPI 측 코드 표면** — authlib 1.7.2(2026-05, OAuth/OIDC 클라이언트+JWT 전부 포함, Starlette/FastAPI 통합 공식 지원)(✅). 카카오·구글 둘 다 OIDC discovery가 있어(✅) provider 등록 각 ~10줄 + 라우트 2개씩. 카카오 `client_secret_post`는 파라미터 하나. 합계 대략 100~200줄 + 테스트.
- **직접 짊어지는 것** — 세션/리프레시 수명 관리 · 로그아웃·탈퇴 플로우 · (JWT 선택 시) 서명 키 회전 · 보안 사고 책임. 1기 표면에선 "DB 세션 테이블 + HttpOnly 쿠키"만으로도 성립해 리프레시 토큰·키 회전을 아예 회피할 수 있다 — 표준 라이브러리 조합의 가장 지루한 형태.
- **무료 티어/벤더** — 해당 없음. 벤더 0, 콘솔은 카카오 디벨로퍼스·구글 클라우드(어느 옵션이든 필요한 그 둘)뿐.
- **판정** — OAuth 코드 플로우 + 쿠키 세션은 20년 검증된 프로토콜을 성숙 라이브러리로 그대로 쓰는 것이라 "발명"이 아니다. 대가는 인증 코드가 우리 리포에 살고 우리가 계속 소유한다는 것.

### 제4 대안 — 관리형 OIDC(Logto) · 자기호스팅(Keycloak류)

- **Logto** — 카카오 **social connector 네이티브**(✅), Free 50k MAU + 소셜 커넥터 3개 + **월 토큰 50k 미터링**(✅), Pro $24/월. 단 `logto_dart_sdk` 3.0.0은 **web 태그 없음**(✅ pub.dev API) — Flutter Web은 결국 서버측 OIDC 플로우로 붙여야 해서 자체 JWT 대비 벤더만 하나 늘어난다. 토큰 미터링이라는 낯선 과금 축도 추가된다. 보류.
- **Keycloak·Ory 등 자기호스팅** — 상주 인프라 + 운영 표면 추가. 1기(사용자 수십 명 이하)엔 명백한 과설계로 **기각**.

## 옵션 비교표

| 축 | Clerk | Firebase Auth | Supabase Auth | 자체 JWT(authlib) | Logto |
| --- | --- | --- | --- | --- | --- |
| Flutter Web SDK | ✗ 없음(베타·커뮤니티 이관) | ✅ 성숙(Favorite) | ✅ 성숙 | 불필요(서버 플로우) | ✗ 없음 |
| 카카오 | custom OIDC만(⚠️) | OIDC=유료 조건 / custom token=이중 구현 | **네이티브** | OIDC 직결(discovery ✅) | 네이티브(커넥터) |
| 구글 | 네이티브 | 네이티브 | 네이티브 | OIDC 직결 | 네이티브 |
| FastAPI 검증 | clerk-backend-api(✅) | firebase-admin(✅) | JWKS+PyJWT(✅) | 자체 발급이라 자명 | 표준 OIDC JWKS |
| 무료 한도 | 50k MRU·소셜 3 | 50k MAU·OIDC는 50 | 50k MAU·1주 무활동 정지 | — | 50k MAU·토큰 50k |
| 벤더/콘솔 추가 | +1 | +1(GCP 정렬) | +1(+Postgres 중복) | 0 | +1 |
| 코드 표면 | 소(단 클라 부재) | 중(카카오 경로가 비대) | **소** | 중(100~200줄+테스트) | 중 |

## 과설계 판정 (축 3) — 1기 표면 대비

1기 최소 인증 표면 = **카카오·구글 소셜 로그인 + FastAPI 검증 가능한 토큰 + 레시피 북 소유자 식별**. 그게 전부다.

| 옵션 | 안 쓰는데 딸려오는 것 | 과잉 비용의 형태 |
| --- | --- | --- |
| Clerk | 조직·멀티테넌트·B2B SSO·매직링크·유저 프로필 UI | 기능 과잉 + **핵심(카카오·Flutter Web)은 결핍** — 최악 조합 |
| Firebase Auth | GCIP 엔터프라이즈 표면(MFA·blocking functions·SAML) | 카카오만 요금·복잡도를 문다(OIDC 50 MAU 또는 custom token 서버 구현) |
| Supabase Auth | Postgres·RLS·스토리지·리얼타임 전부(요금은 안 묾) | 기능 과잉이되 무과금 — 대신 DB 이중화·정지 정책이라는 구조 비용 |
| 자체 JWT | 없음 | 과잉 0, 대신 부족분(세션·키·보안 책임)을 코드로 직접 지불 |
| Logto | 조직·RBAC·MFA·토큰 미터링 과금 축 | 1기 표면 대비 제품 지향이 다름 + Flutter Web SDK 부재 |

## 결론 프레임 — 표준 추출 원칙 적용 (#74 Notes)

표준은 추상에서 발명하지 않는다 — 첫 소비자(냉파 1기)의 실요구에서 추출하고, 동률이면 지루하고 검증된 쪽을 택한다. 1기 실요구에서 추출하면 **2강 = Supabase Auth vs 자체 JWT**이고 나머지는 사실 관계로 탈락한다.

- **Clerk ★☆☆☆☆** — Flutter Web 클라이언트가 없어 1기에 성립 불가(사실 탈락). backend.md §9는 웹(JS) 스택 전제의 표준으로 남기되, 냉파 편차를 ADR-0009에 기록해야 한다.
- **Firebase Auth ★★☆☆☆** — 구글·Flutter Web은 최상이나 핵심 판별자(카카오)에서 요금 조건 또는 이중 구현을 강요. GCP 정렬 가산점으로도 상쇄가 안 된다.
- **Logto ★★☆☆☆** — 카카오 네이티브는 매력이나 Flutter Web SDK 부재·토큰 미터링·벤더 추가로 2강 대비 우위가 없다.
- **Supabase Auth ★★★★☆** — 1기 표면을 최소 코드로 정확히 덮는 유일한 관리형(카카오·구글 네이티브 + 표준 JWKS 검증 + 성숙한 Flutter Web SDK). 감수점 — 무활동 1주 정지, Neon과의 DB 이중화(FK 불가·RLS 미활용), 벤더 +1.
- **자체 JWT(FastAPI+authlib) ★★★★☆** — 벤더 0, #76 same-origin 결정과 최고 정합(HttpOnly 쿠키), 카카오·구글 모두 표준 OIDC 직결. 감수점 — 세션·키·보안 책임을 코드로 소유(1기 표면 기준 100~200줄+테스트).

동률(★4 vs ★4)의 타이브레이커 "지루하고 검증된 쪽"은 읽기가 갈린다 — **읽기 A**: "인증은 직접 만들지 않는다"가 업계의 지루한 통념이므로 Supabase. **읽기 B**: Supabase를 Auth 전용으로 쓰는 건 비정형 사용(DB 이중화)이고, OIDC 코드 플로우+쿠키 세션은 20년 검증 프로토콜의 가장 지루한 사용이므로 자체 JWT. 이 타이브레이커 판정 자체가 **#77 그릴링의 질문**이다 — 본 문서는 결정하지 않는다.

## 출처

[clerk_flutter (pub.dev)](https://pub.dev/packages/clerk_flutter) · [clerk_auth (pub.dev)](https://pub.dev/packages/clerk_auth) · [clerk_flutter README(community-maintained 명시)](https://github.com/clerk/clerk-sdk-flutter/blob/main/packages/clerk_flutter/README.md) · [clerk-sdk-flutter #237 web 지원 요청](https://github.com/clerk/clerk-sdk-flutter/issues/237) · [#362 web 지원 PR](https://github.com/clerk/clerk-sdk-flutter/issues/362) · [#427 웹 Sign out 불능](https://github.com/clerk/clerk-sdk-flutter/issues/427) · [#433 커뮤니티 이관](https://github.com/clerk/clerk-sdk-flutter/issues/433) · [Clerk 퀵스타트 목록](https://clerk.com/docs/quickstarts/overview) · [Clerk 가격](https://clerk.com/pricing) · [Clerk custom OIDC provider](https://clerk.com/docs/guides/configure/auth-strategies/social-connections/custom-provider) · [clerk-docs social-connections 디렉토리(kakao 부재)](https://github.com/clerk/clerk-docs/tree/main/docs/guides/configure/auth-strategies/social-connections) · [clerk-backend-api (PyPI)](https://pypi.org/project/clerk-backend-api/) · [firebase_auth (pub.dev)](https://pub.dev/packages/firebase_auth) · [Firebase Flutter federated auth](https://firebase.google.com/docs/auth/flutter/federated-auth) · [Firebase 가격(SAML/OIDC 50 MAU)](https://firebase.google.com/pricing) · [Firebase web OIDC(Identity Platform 필수)](https://firebase.google.com/docs/auth/web/openid-connect) · [Firebase ID 토큰 검증](https://firebase.google.com/docs/auth/admin/verify-id-tokens) · [flutterfire #11591](https://github.com/firebase/flutterfire/issues/11591) · [supabase_flutter (pub.dev)](https://pub.dev/packages/supabase_flutter) · [Supabase Kakao 로그인 가이드](https://supabase.com/docs/guides/auth/social-login/auth-kakao) · [Supabase 가격(1주 정지 정책)](https://supabase.com/pricing) · [Supabase JWT/JWKS 검증](https://supabase.com/docs/guides/auth/jwts) · [카카오 OIDC discovery(라이브)](https://kauth.kakao.com/.well-known/openid-configuration) · [카카오 로그인 공통 가이드](https://developers.kakao.com/docs/latest/ko/kakaologin/common) · [카카오 비즈앱·이메일 필수 동의(데브톡)](https://devtalk.kakao.com/t/topic/132350) · [kakao_flutter_sdk_user (pub.dev)](https://pub.dev/packages/kakao_flutter_sdk_user) · [Authlib (PyPI)](https://pypi.org/project/Authlib/) · [Logto Kakao 커넥터](https://docs.logto.io/integrations/kakao) · [Logto 가격](https://logto.io/pricing) · [logto_dart_sdk (pub.dev)](https://pub.dev/packages/logto_dart_sdk)
