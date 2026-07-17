# apps/api를 실체화한다 — ADR-0005의 "로그인·서버 DB 없음" 부분 역전

2026-07-17 사용자 결정으로 `apps/api`(FastAPI + SQLModel)를 실체화하고, ADR-0005가 고정한 MVP 범위 중 **"로그인·서버 DB 없음"을 부분 역전한다.** ADR-0008이 이 역전을 "미래 wayfinder 지도에서 나올 자기 ADR"로 예약해 뒀고, 지도 [#74](https://github.com/woosung-dev/cookmark/issues/74)가 그 지도다. 이 ADR은 그 지도의 결정 8개(범위 [#75](https://github.com/woosung-dev/cookmark/issues/75) · 스택·배포 [#76](https://github.com/woosung-dev/cookmark/issues/76) · 인증 [#77](https://github.com/woosung-dev/cookmark/issues/77) · 계약 [#81](https://github.com/woosung-dev/cookmark/issues/81) · 데이터 이전 [#86](https://github.com/woosung-dev/cookmark/issues/86) · 데이터 보호 [#87](https://github.com/woosung-dev/cookmark/issues/87) · 인프라 [#88](https://github.com/woosung-dev/cookmark/issues/88) · 접속 [#94](https://github.com/woosung-dev/cookmark/issues/94))를 **1회로 접어 기록**하며, 각 티켓의 해소 코멘트가 그 결정의 정본이다.

**동기를 정직하게 — 제품 수요가 아니라 표준 검증이 주목적이다.** 지도 Destination이 *"회사 표준 설계가 주목적이고 냉파는 첫 적용 사례다"*라 적었고, #75가 로그인+레시피 북을 고른 이유도 *"user-scoped CRUD로 DB·인증·마이그레이션 표면을 전부 밟는 유일한 냉파 도메인"*이기 때문이다. 파일럿 판정(~8/5)을 기다리지 않고 착수한다.

**부분 역전임에 주의** — ADR-0005의 나머지는 살아 있다. 제품 정본은 여전히 Flutter 단일 코드베이스이고([#78](https://github.com/woosung-dev/cookmark/issues/78)이 `apps/web`을 기각하며 재확인), Web 빌드는 파일럿 임시이며 네이티브로 전환한다. "API 키는 클라이언트에 두지 않는다"도 그대로다 — 프록시가 서버리스 함수에서 `apps/api`로 옮겨갈 뿐이다.

## 1기 범위 (#75)

- **코어 = 로그인 + 서버 레시피 북.** `idea.md` SaaS 구상의 최소 코어만 부활한다 — 과금·제휴·영양은 부활하지 않는다.
- **이월 2건 포함** — 매칭 % 실산출(매치 점수 반환 + `Suggestion` 스키마 변경 수반) · 음식사진 og:image 프록시(웹 CORS 우회).
- **기존 프록시 3개(recognize·extract·match) 전량 승계.** LLM 호출 표면이 Vercel(`.mjs`)과 FastAPI로 갈라지면 `backend.md` §4(`ai_processing.py` 집중)가 깨지고 운영이 이중화된다. 루트 `api/`는 **승계 완료 + 파일럿 종료 후 단순 삭제**한다([#83](https://github.com/woosung-dev/cookmark/issues/83)) — Vercel rewrite로 조기 컷오버하는 안은 기각됐다(웹 prod가 파일럿 전용이라 갈아끼울 트래픽이 없다).
- **서버 보관 경계 = 레시피 북(+계정)만.** 사진은 무저장 패스스루(현행 유지), **이벤트 로그는 클라이언트 로컬 정본**(ADR-0003 · P2 킬 산식), 인식 결과 기록은 2기 후보.

## 스택·배포 (#76 · #88)

- **`.claude/rules/backend.md` 표준 전량 채택** — FastAPI + SQLModel + Neon + `uv` + 100% async. 내부 레이아웃은 §11을 따르되 위치는 `apps/api/src/…`(ADR-0008 화해 조항).
- **편차 2곳** — ① **§4는 구조만 채택**(LLM 호출 집중 · `BaseLLMService` 추상화 · 프롬프트 상수화)하고 구현체는 **google-genai**다(승계 프록시 3개의 Gemini flash-lite 연속성 + 원가 $0.0011/루프 승계). §4의 "Claude/anthropic" 명시는 프로바이더 교체 가능한 일반형으로 읽는다. ② **§9(인증)는 아래 인증 절이 전면 교체**한다.
- **배포처 = Google Cloud Run 서울(유료 리전).** GCP 생태계 정렬(Gemini 동일 벤더) · Docker 네이티브(§8 "Docker entrypoint에서 `alembic upgrade head`" 전제 충족) · 사용자(한국) 근접. **무료 등급(US 3리전 한정)은 의식적으로 포기**했다 — 조사 [#82](https://github.com/woosung-dev/cookmark/issues/82)의 권고(싱가포르 상주)와 갈린 결정이다.
- **DB = Neon 싱가포르(ap-southeast-1) 유지** — 표준 무편차. 서울↔싱가포르 왕복 ~60-70ms/쿼리(CRUD 2-3쿼리 기준 요청당 +150~200ms)를 감수한다. **재검토 트리거 = CRUD p95 체감 불만.** `asyncpg` + Neon PgBouncer는 `statement_cache_size=0` **필수**(#82 함정).
- **인스턴스 = scale-to-zero(min-instances=0).** 콜드스타트 1~3초는 LLM 지배 루프에서 부차적. **승격 트리거 = 실사용자 유입 또는 체감 불만.**
- **배포 = GitHub Actions 자동 배포 + Workload Identity Federation**(키 파일 없음). main push → 이미지 빌드 → Cloud Run 배포. CI가 이미 GitHub Actions라 한 곳에 모인다.
- **시크릿 = Secret Manager(비밀) + 환경변수(비-비밀 설정) 분리.** 1기 비밀 5개 — `GEMINI_API_KEY` · `DATABASE_URL` · `KAKAO_CLIENT_SECRET` · `GOOGLE_CLIENT_SECRET` · 세션 서명/암호화 키. Cloud Run `--set-secrets`가 env로 주입하므로 **앱 코드 변경 0**이다. `CORS_ALLOWED_ORIGINS` 같은 비-비밀은 env로 남긴다. **로컬 개발은 Secret Manager를 보지 않는다** — `.env.local`이 로컬 정본이다.
- **모니터링 = Cloud Run 기본**(Cloud Logging + Monitoring). 소비자가 0명이므로 별도 벤더를 늘리지 않는다. **승격 트리거는 위 인스턴스 승격과 공유**한다.
- **`infra/` = IaC 미도입** + `infra/README`에 프로비저닝 절차(Cloud Run 서비스 1 · 시크릿 5 · WIF 풀 1). **Terraform 도입 트리거 = 환경 2개째(staging) 또는 인프라 변경자 2명째** — IaC의 실요구가 둘 다 없고, state 백엔드를 먼저 프로비저닝해야 하는 닭-달걀이 붙는다.

## 접속 (#94)

- **`apps/mobile` → `apps/api`는 절대 URL 직접 호출**이다. `COOKMARK_API_BASE`(이미 `apps/mobile/lib/llm/proxy_llm_gateway.dart`에 `String.fromEnvironment`로 존재)에 Cloud Run URL을 주입하고, 로컬·네이티브·웹이 **단일 네트워킹 경로**를 쓴다.
- **Vercel external-origin rewrite 경유는 채택되지 않는다.** #76이 잠시 그렇게 정했으나 #94가 역전했다 — rewrite가 봉사할 소비자가 없다(네이티브는 origin 자체가 없고 · 로컬 개발은 이미 cross-origin이며 · 파일럿 웹은 `apps/api`를 소비하지 않는다). `vercel.json`은 **수정하지 않는다**(그 rewrite는 배선된 적이 없다).
- **경로 = `/api/v1` 프리픽스 유지.** 네이티브 앱은 앱스토어 구버전 클라이언트가 강제 업데이트 없이 몇 달 살아남으므로 버저닝이 실질 값을 한다.
- **CORS는 필요하다** — #76이 적은 "CORS 없음"은 달성 불가능한 목표였다. #83이 첫 소비를 로컬로 확정한 순간 `flutter run -d chrome`(localhost 임의 포트) → 로컬 FastAPI(8000)가 cross-origin이 된다. **1기 허용 origin = 로컬 개발 origin뿐**이다.
- **prod 웹의 `apps/api` 소비는 이 ADR이 정하지 않는다**(#83 "로컬 우선" 연장).

## 인증 (#77)

- **자체 OIDC 세션 인증(FastAPI + authlib).** `backend.md` §9의 Clerk는 **전면 교체**된다 — Clerk는 Flutter Web 클라이언트가 부재해 1기가 성립하지 않는다([#89](https://github.com/woosung-dev/cookmark/issues/89)). Supabase Auth는 Auth 전용 사용이 비정형(Neon과 DB 이중화·FK 불가)이고 무활동 1주 정지가 로그인 장애 지뢰라 기각했다.
- **세션 = 앱 소유 관계형 DB의 세션 테이블.** 운반은 웹이 불투명 세션 ID를 HttpOnly·Secure·**SameSite=Lax** 쿠키로, 네이티브가 같은 토큰을 보안 저장소(Keychain/Keystore) + `Authorization: Bearer`로. 저장 방식은 하나, 운반만 플랫폼별이다.
  - **Lax의 근거가 #94로 교체됐음에 주의.** #77은 *"#76의 same-origin `/api/v1` 위에 자연 성립한다"*고 적었는데 그 same-origin이 사라졌다. **결론은 살아남았고 근거만 바뀌었다** — SameSite는 origin이 아니라 site 기준이고 **포트는 site 판정에 들어가지 않으므로**, 로컬(`localhost:임의포트` → `localhost:8000`)은 cross-origin이지만 **same-site**라 Lax 쿠키가 정상 전송된다.
  - **트립와이어** — 배포된 웹이 `apps/api`를 소비하게 되면(`*.vercel.app` → `*.run.app`) cross-site라 Lax가 차단된다. 그때 `SameSite=None; Secure` + CSRF 대책을 재결정한다. 없는 소비자를 위해 지금 CSRF 표면을 선지불하지 않는다.
- **stateless JWT 미채택** — 즉시 폐기 불가(로그아웃·탈퇴·차단이 만료 대기 또는 블랙리스트 = 세션 표면 이중 지불) · 서명 키 운영 소유 · 리프레시 눈덩이. 구현 표면도 세션(~30-50줄)이 JWT+리프레시(~150-300줄+키 운영)보다 작다. **전환 트리거 = 검증 주체가 여러 서비스로 분산되거나 세션 조회가 병목이 될 때.**
- **1기 소셜 = 카카오·구글.** 카카오는 표준 OIDC IdP다(`client_secret_post`는 authlib 파라미터 1개). **애플 로그인은 1기 제외** — 트리거는 "iOS 네이티브 출시 시 의무"(App Store 심사 4.8).
- **provider의 ID 토큰은 로그인 순간 1회 검증 후 폐기**하며 우리 API의 세션 증표로 재사용하지 않는다. provider를 몇 개 붙이든 세션 방식과 무관하다.

## 데이터 경계·보호 (#87 · #86)

**회사 표준(제품 중립)은 `backend.md` §12 「데이터 보호 — 최소수집·격리·파기」가 정본이다.** 이 절은 **냉파 고유 사실**만 적는다 — 둘을 섞으면 회사 표준이 냉파에 오염된다.

- **서버에 보관하는 것** — 계정(`내부 id, iss, sub, created_at`)과 레시피 북. 그게 전부다. **사진은 무저장 패스스루**이고 **이벤트 로그는 클라이언트 로컬 정본**이다.
- **레시피 북 = 서버 정본 + 로컬 캐시 없음**(#86). 근거는 **이 앱이 오프라인에서 코어 루프가 죽는다**는 것이다 — 재료 인식·매칭이 전부 LLM 호출이라 네트워크 없이는 사진을 올려도 재료가 안 나온다. 레시피 북만 오프라인 정본으로 남겨도 **살릴 루프가 없다.** 캐시는 오프라인 열람이 실요구로 발현하면 그때 얹는다.
  - **로컬 스토리지 모듈(`apps/mobile/lib/data/storage.dart`)은 그대로 산다** — 이벤트 로그가 로컬 정본이므로. "로컬 영속은 단일 스토리지 모듈로만"(ADR·`coding-standards.md`) 불변식은 **무변경**이다.
- **로컬 레시피 북의 이전 = 명시적 가져오기**(#86). 로그인 후 로컬에 레시피가 있으면 1회 안내 → 확인 → bulk POST → **업로드 성공 확인 후** 로컬 삭제(실패 시 유지). 자동 병합은 기각했다 — 한 기기에 다른 계정이 로그인하면 남의 로컬 레시피가 조용히 그 계정으로 올라간다.
  - **이 이전 코드는 시한부다.** 대상은 파일럿 가구 2명이고 서버 정본 체제에선 사용자당 평생 1회 발화한다. **두 계정 이전 완료 시 제거한다.**
- **파일럿 판정 원본(export JSON 2개)은 서버에 가지 않는다** — 파운더 로컬 폴더가 보관처다(`CONTEXT.md` 주간 백업 정의). 이전은 판정 후에 일어나므로(파일럿 종료 → 판정 → #38 → BE 소비) 판정을 훼손할 수 없다.
- **개인정보처리방침 트리거** — 로그인을 붙이면 `sub`도 식별자라 PIPA상 처리방침 공개 **의무**가 생긴다. **1기 공개 전에 필요하며, 사내 스터디·파일럿 단계에선 미발화**다. 결정이 아니라 의무·실행이라 지도 Out of scope였고, 잊히지 않도록 여기 트리거로 남긴다.

## 계약 (#81) — ADR-0008의 "계약 우선" 선언을 역전한다

- **코드 우선 + 커밋된 스냅샷 + CI 드리프트 가드.** **Pydantic 모델이 정본**이고 `contracts/openapi.yaml`은 **생성물**이다. 커밋하는 목적은 스키마 변경이 PR diff로 보이게 하는 것이다.
- **역전 사유** — 차팅 시점의 좌표 선언보다 채택된 스택이 이긴다. FastAPI는 구성상 코드 우선이고, `backend.md` 검증 앵커의 `schemathesis`조차 **생성된 스키마를 읽는다.** "계약 우선"을 고수하면 표준과 첫 적용 사례가 첫날부터 어긋난다.
- **계약은 `apps/api`의 첫 라우트가 낳는다.** 프록시 3개는 수기 문서화하지 않는다 — #75가 폐지를 확정한 코드이고 `.mjs` 소스가 승계 입력이자 정본이다.
- **가드 = CI 전용 차단**(재생성 → diff 있으면 PR 차단, 자동 커밋 없음, 갱신은 사람이 로컬 재생성 명령으로). `mobile.yml`의 "포맷 미적용 = 실패"와 동형이다.
- **`contracts/`는 발행 지점이지 상류가 아니다** — colocate 관례의 명시적 예외다(언어·앱 횡단 발행점이라 소비자가 producer 내부 경로를 참조하지 않게 한다).
- **하류 클라이언트는 원칙 생성 강제 · 채택은 트리거.** `packages/api-client-ts`는 TS 소비자 부재로 좌표 유지, `packages/api-client-dart`는 **미채택**(수기 Dio + 계약 드리프트가 실결함으로 발현 시 재결정 — `mobile.md` §8의 package 분리 트리거가 구조적으로 영구 미충족이다).

## Considered Options

- **"이월 2건만" 백엔드** — 기각. 매칭 %·og:image는 둘 다 무상태 프록시라 표준 백엔드의 첫 소비가 못 되고 `apps/api` 실체화 근거가 성립하지 않는다.
- **Vercel Python Functions** — 사실상 제외. Docker 경로가 없어 `backend.md` §8(Docker entrypoint 마이그레이션) 전제와 충돌한다([#82](https://github.com/woosung-dev/cookmark/issues/82)).
- **Supabase Auth / Clerk** — 기각. 위 인증 절 참조.
- **오프라인 정본 유지 + 양방향 동기화** — 기각. 충돌 해소를 1기에 끌어들이고 정본을 둘로 만드는데, 오프라인에 살릴 루프가 없다.
- **RLS로 격리** — 미채택. 사유와 트리거는 `backend.md` §12가 정본이다(요지 — 우리 구조에선 RLS를 직접 배선해야 하고 그 실패 모드가 조용하며, 진짜 안전망은 결국 교차 테넌트 테스트다).
- **IaC(Terraform) 즉시 도입** — 기각. 위 인프라 절 참조.

## Consequences

- **ADR-0005는 부분적으로만 산다.** "로그인·서버 DB 없음"은 죽었고, "Flutter 단일 코드베이스 · Web 빌드는 파일럿 임시 · API 키 클라이언트 금지"는 유효하다. ADR-0005 본문은 시점 기록이므로 소급 수정하지 않는다(그 ADR 자신의 실측 주석 선례).
- **ADR-0008의 두 선언이 정정된다** — ① `contracts/`의 "계약 우선"·"상류" 표현(29·30·31·35행) ② `infra/`의 "자동 배포 금지 규약의 정신"(36행). 후자는 **#57을 오독한 것**이다 — #57은 Flutter-Web-on-Vercel 특정 버그(`buildCommand: null` + gitignored `build/web` → 빈 정적 배포) 대응이고 본문 스스로 잠정이라 적었으며, **그 실패 모드는 Cloud Run에 구조적으로 없다**(파이프라인이 이미지를 빌드한다). **Vercel prod의 수동 프리빌드 규약은 `apps/mobile`에 한정해 그대로 유지된다** — 둘을 한 규칙으로 묶지 말 것.
- **`backend.md`(gitignored 로컬 정본)가 4곳 바뀐다** — §9 전면 교체(Clerk 삭제) · §12 신설(데이터 보호) · CORS 절 신설 · 계약 절 신설. 표준은 회사 자산이라 리포 밖에 살며 이 PR에 포함되지 않는다.
- **`apps/mobile`은 이 ADR로 인해 지금 바뀌지 않는다.** BE 소비는 #38 랜딩 후이고 첫 소비는 로컬이다([#83](https://github.com/woosung-dev/cookmark/issues/83)). 파일럿 무접촉 가드(~8/5)는 유지된다 — `apps/api`는 별도 앱·별도 배포라 파일럿과 절연된다.
- **부정적 결과를 정직하게** — 자체 인증은 세션·소셜 연동을 직접 소유한다는 뜻이고(벤더 0의 대가), Neon 싱가포르 유지로 요청당 +150~200ms를 감수하며, Cloud Run 서울은 무료 등급을 포기한다. 이전 코드·`infra/` 절차 문서는 트리거로만 정당화되는 임시물이라 만료를 지켜야 한다.
- **다음 단계** — 이 ADR이 발행되면 지도 [#74](https://github.com/woosung-dev/cookmark/issues/74)가 닫히고 스펙 트랙(`/to-spec` → `/to-tickets`)이 열린다.
