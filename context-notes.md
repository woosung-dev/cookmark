# Context Notes — #100 api-4 인증 (카카오·구글 OIDC 세션 + 탈퇴 하드 삭제)

자율결정 감사 추적. 결정/근거 1줄씩 append. 계획: `~/.claude/plans/100-auth-oidc-session.md`.

## 스코프 경계 (착수 전 확정)

- **#100 = 인증 수직 슬라이스만.** 레시피 북 CRUD·스코프드 Repository는 #103, LLM 승계는 #101, 배포·Secret Manager는 #98, OpenAPI 스냅샷·드리프트 가드는 #99 — 이 PR에 넣지 않는다.
- 루트 `api/`(.mjs 프록시)·`vercel.json`·`apps/mobile` 무접촉 (파일럿 가드 ~8/5).
- 병렬 worktree 있음(#98·#99) — 공유 파일(`conftest.py`·`main.py`·`config.py`) 편집은 최소 표면으로.

## 결정 로그 (착수 전)

- **세션 토큰은 DB에 SHA-256 해시로만 보관** — 원문 보관 시 DB·백업 유출이 곧 세션 탈취다. ADR-0009가 PITR 백업 잔존을 명시적으로 인정하므로(§12.3), 그 잔존물이 살아있는 세션이면 안 된다. 표면 +3줄. 티켓은 "불투명 세션 ID"만 요구하고 해시를 요구하진 않았다 — 자율 판단.
- **`expires_at` 포함, TTL 30일 모듈 상수** — 쿠키 `Max-Age`의 서버측 짝이 없으면 토큰이 영구 유효해진다(쿠키만 만료되고 Bearer로는 계속 통과). 설정 노브는 안 만든다(요구 없음). 만료 행 청소 잡은 범위 밖 — 트리거 = 행 증가가 실문제화.
- **계정 중복 방지 = UNIQUE(iss, sub) DB 제약** — "조회 후 없으면 생성" 관례가 아니라 구조로 막는다(§12.2의 정신).
- **`SessionMiddleware`는 우리 인증 세션이 아니다** — authlib의 OAuth state·nonce 운반 전용(itsdangerous 서명 쿠키, 수명 10분 = 인가 화면에 머무는 시간). ADR-0009 비밀 5개 중 "세션 서명/암호화 키"의 소비처가 정확히 여기다. 우리 세션은 DB 테이블이고 불투명 ID다(§9).
- **콜백 응답 = 쿠키 + JSON(토큰 포함)** — 리다이렉트 대상은 소비할 FE가 1기에 없어(스펙 Out of Scope: `apps/mobile` 무변경) 설정 선지불이다. 토큰을 본문에 넣는 근거는 #77 "같은 불투명 토큰을 네이티브가 Bearer로" — 본문 말고는 비-브라우저 클라이언트가 토큰을 얻을 경로가 없다. **트리거 = FE 소비 시 리다이렉트 재결정.**
- **`redirect_uri` = `request.url_for`** — 설정 0으로 로컬 데모가 성립한다. Cloud Run HTTPS 프록시 헤더(`--forwarded-allow-ips`) 배선은 #98의 몫이며, 그때 x-forwarded-proto가 없으면 http URL이 나가 IdP 등록값과 어긋난다는 것이 인수인계 사항.
- **provider 자격증명은 필수 필드(placeholder 아님)** — 없으면 부팅 실패가 조용한 로그인 장애보다 낫다. `.env.local`(gitignored)에 로컬 값, 배포는 Secret Manager(#98).

## 구현 중 발견·결정 (append)

- **authlib 1.7.2의 `authorize_access_token`은 ID 토큰 검증을 조용히 건너뛴다(fail-open).** 검증은 `"id_token" in token and "nonce" in state_data`일 때만 돌고, `nonce`는 `authorize_redirect`가 scope에서 리터럴 `"openid"`를 봤을 때만 저장된다. **카카오는 콘솔 토글만 켜져 있으면 scope와 무관하게 id_token을 준다** → `openid`가 빠지면 에러 없이 미검증 토큰을 쥔다. 방어 — `SCOPE = "openid"`를 설정이 아닌 모듈 상수로 고정 + `token.get("userinfo")`의 소프트 폴백 금지(폴백이 곧 인증 우회다). **실측 확인** — SCOPE에서 openid를 빼는 뮤테이션으로 로그인 테스트 7건이 실패한다(= fail-closed).
- **`authlib.jose`는 1.7.2에서 deprecated** — 테스트 서명은 `joserfc`(authlib 전이 의존)로 한다. 2.0.0에서 제거 예정.
- **respx는 ASGITransport를 건드리지 않는다(실측).** 기본 mocker가 httpcore 계층을 패치하는데 `httpx._transports.asgi`는 httpcore를 import하지 않는다 — 앱 구동(ASGI)과 앱의 아웃바운드 mock이 한 테스트에서 공존한다. `using="httpx"`를 주면 오히려 깨진다.
- **`sa_type=DateTime(timezone=True)`는 mypy strict에서 call-overload 에러** — `sa_column=Column(DateTime(timezone=True), nullable=False)`로 쓴다. 런타임은 둘 다 되지만 게이트가 막는다.
- **`Relationship()`을 두지 않은 건 의도다** — 관계를 걸면 계정 삭제 시 SQLAlchemy가 `account_id`를 NULL로 UPDATE하려다 NOT NULL을 위반한다. 파기는 DB의 ON DELETE CASCADE에 맡긴다(실 DB에서 `confdeltype='c'` 확인).
- **`AccountRepository.add`가 flush하는 이유** — Relationship이 없어 SQLAlchemy가 accounts↔sessions 의존을 모른다. flush로 INSERT 순서를 고정하지 않으면 FK 위반 가능.
- **`script.py.mako`에 `import sqlmodel` 추가** — SQLModel의 `str` 필드가 `sqlmodel.sql.sqltypes.AutoString`으로 렌더돼 import 없으면 마이그레이션이 `NameError`로 죽는다.
- **`alembic check`를 CI 스텝이 아니라 pytest로 복원**(#97 env.py가 이 티켓에 맡긴 숙제) — 실 DB가 있어야 도는 검사인데 testcontainers가 이미 띄운다. CI에 서비스 컨테이너를 따로 배선할 이유가 없다. sync 테스트인 이유는 env.py가 `asyncio.run()`으로 돌기 때문. **뮤테이션으로 검증** — 모델에 컬럼을 더하면 실패한다.
- **`redirect_uri`는 Host 헤더에서 나온다(실측)** — `localhost:8000`으로 열면 등록값과 맞고 `127.0.0.1:8000`으로 열면 같은 서버인데 거절된다. README 데모 절에 적었다. Cloud Run 프록시 헤더는 #98 인수인계.
- **CORS 와일드카드 거부 validator 추가** — 이 티켓이 `allow_credentials=True`를 켜서 생긴 직접 결과다. Starlette은 `credentials + "*"` 조합에서 `*`를 요청 origin 반향으로 바꿔 **아무 origin이나 통과**시킨다(스펙상 불법 조합을 조용히 우회). §9.1의 산문 금지를 구조로 옮겼다.
- **콜백 실패는 전부 401** — 서명 불일치·state 불일치·동의 거부를 `IdentityUnavailable` 하나로 모아(변환 1곳) 라우터가 401로 옮긴다. 동의 거부는 400이 더 맞다는 견해가 있으나 표면을 하나로 둔다.
- **로그아웃은 멱등(무세션도 204)** — "로그아웃 = 세션 행 삭제"가 전부고, 죽은 증표로 불러도 결과가 같다. 표준적 선택이며 `/me`·탈퇴의 401과 층위가 다르다(증표 파기 vs 증표 요구).
- **구글 `iss` 오버라이드(`claims_options`)는 채택하지 않았다.** 리서치는 `values: ["https://accounts.google.com", "accounts.google.com"]` 허용을 권했으나, **두 형태를 다 받으면 같은 사람이 계정 2개로 갈린다**(iss가 계정 키의 일부다). 기본값이면 bare 형태는 로그인 실패로 **시끄럽게** 터진다 — 조용한 계정 분열보다 낫다. 실제로 구글은 코드 플로우에서 `https://` 형태를 준다. **트리거 = 파운더 데모에서 iss 불일치가 나면 그때 정규화로 재결정.**
- **미채택: metadata naming_convention** — 그린필드에 넣는 게 정석이나(제약 rename이 나중엔 아프다) 티켓 범위 밖이고 `SQLModel.metadata`는 #103 테이블과 공유된다. 지금 비용 ~7줄, #103 후 비용도 아직 낮다. **사용자 판단 사항으로 올린다.**
- **미처리: 신규 (iss, sub) 동시 로그인 경합** — UNIQUE 위반으로 한쪽이 500, 사용자가 재시도하면 성공. 발현 조건이 좁아(같은 신규 사용자의 동시 첫 로그인) 1기 감수. 트리거 = 실제 발현.

## 코드리뷰 반영 (2축)

리뷰 결과 — Standards 하드 위반 0, Spec 결함 1(실재·수정함).

- **[Spec·실결함] `test_migrations.py`가 전체 스위트에서 항상 실패했다** — 단독 실행만 해보고 전체를 안 돌린 내 누락이다(전체 스위트는 이 파일 추가 **전**에 돌렸다). 원인은 추측이 아니라 실측 — `get_engine()`이 lru_cache라 풀에 pytest-asyncio 세션 루프의 커넥션이 남는데, `command.check()`가 `asyncio.run()`으로 **새 루프**를 만들어 그걸 재사용하다 asyncpg가 `attached to a different loop`로 터진다. **고친 위치 = env.py**(호출부가 아니라) — 자기 루프에서 도는 걸 아는 모듈이 거기다. `dispose(close=False)`로 **실행 전에** 풀만 버린다(남의 루프 커넥션은 닫으려 드는 순간 같은 이유로 터지므로 close=False가 필수). 뒷정리 dispose는 #97이 이미 넣어둔 대칭짝이었다 — 앞쪽이 비어 있었다.
- **[Standards] `# type: ignore` 3개 제거** — `_COOKIE_KWARGS` dict 언패킹이 시그니처 매칭을 깨서 붙였던 것. 타입 있는 `_set_session_cookie`/`_clear_session_cookie`로 바꿔 ignore 0·중복 0. 테스트의 `count_rows(statement: object)`도 `Select[tuple[int]]`로 정직하게.
- **[Standards·수용] `auth_callback`이 §3의 "라우터 10줄 이하"를 넘는다(~13줄)** — authlib이 `Request`를 요구하고 §3은 서비스가 `Request`를 아는 걸 금지하므로 이 왕복은 라우터에 남을 수밖에 없다. 비즈니스 로직·DB 접근은 0이라 규칙의 의도("HTTP 전용")는 지킨다.
- **[Standards·수용] repo `commit()` 2개가 동일 1줄** — §3이 commit을 Repository에 두라고 규정한 결과다(같은 session을 공유하니 어느 쪽을 불러도 같다). 서비스가 session을 들면 §3 위반이라 seam을 하나로 못 줄인다. login의 §3 주석이 이걸 설명한다.
- **[Standards·수용] `kakao_client_id`가 `SecretStr`이 아니다** — OAuth `client_id`는 authorize URL에 실려 나가는 공개값이라 비밀이 아니다. 카카오가 "REST API 키"라 부르는 게 혼동의 원인. `client_secret`만 `SecretStr`이다.
- **CI 조건 확인** — `.env.local`을 치우고(=CI 환경) 전체 스위트 green 확인. 병렬 #99 세션이 "`.env.local`이 로컬 green을 가린다"는 함정을 남겨 교차 확인했다.
