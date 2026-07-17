# apps/api — 냉파 백엔드 (FastAPI + SQLModel)

루트 `api/` 서버리스 프록시의 승계자. 스펙 [#96](https://github.com/woosung-dev/cookmark/issues/96) · ADR-0009로 실체화됐다 (#97 walking skeleton 로컬 절반). 규율 rules는 `.claude/rules/backend.md` — 내부 레이아웃은 §11을 `apps/api/src/`로 읽는다.

## 구동 (이 디렉토리에서)

```bash
uv sync                                  # 의존성 (.python-version 3.13 핀)
uv run uvicorn src.main:app --host 0.0.0.0 --port ${API_PORT:-8000} --reload
curl http://localhost:8000/api/v1/health # → {"status":"ok"}
```

## 검증 (backend.md 검증 앵커)

```bash
uv run ruff format --check .   # 포맷 (미적용 = 실패)
uv run ruff check .            # 린트
uv run mypy src/ scripts/      # 타입 (strict + pydantic 플러그인)
uv run pytest                  # 통합(ASGI + testcontainers 실 Postgres — Docker 필요) + 유닛
uv run alembic upgrade head    # 마이그레이션 적용 (--sql로 dry-run)
uv run alembic check           # 모델↔마이그레이션 드리프트 (실 DB 필요 — pytest가 같은 검사를 컨테이너에서 돌린다)
```

## 계약 (OpenAPI)

**Pydantic 모델이 정본**이고 `contracts/openapi.yaml`은 **생성물**이다 (ADR-0009 계약 절). 스키마를 바꿨으면 재생성해 **같은 커밋에 포함**한다 — 잊으면 CI가 막는다 (자동 커밋 없음).

```bash
uv run python scripts/export_openapi.py           # 재생성
uv run python scripts/export_openapi.py --check   # 드리프트 검사 (CI 가드와 동일)
```

`schemathesis`는 발행된 계약을 **실 서버**에 물려 구현이 계약을 지키는지 fuzzing한다 — CI 게이트이고, 로컬 재현은 아래처럼 한다. 실 서버인 이유는 v4가 CLI의 인프로세스 ASGI를 제거했고 남은 인프로세스 경로가 sync `TestClient`(§10 금지)이기 때문이다.

```bash
uv run uvicorn src.main:app --port 8090 &        # health는 DB 미접촉 — DATABASE_URL은 자리표시자로 족하다
uv run st run ../../contracts/openapi.yaml --url http://localhost:8090
```

CI는 `.github/workflows/api.yml`이 매 PR(`apps/api/**` paths 필터)·main push(무필터 백스톱)에서 위 게이트를 강제한다.

## 설정 — 로컬 정본은 `.env.local` (gitignored)

| 변수 | 설명 |
| --- | --- |
| `DATABASE_URL` | `postgresql+asyncpg://…` — SecretStr. Neon PgBouncer 대비 `statement_cache_size=0`은 코드가 강제 |
| `CORS_ALLOWED_ORIGINS` | 콤마 구분 허용 origin. **기본 빈 목록** — 필요한 환경에서만 켠다. 와일드카드·regex·하드코딩 금지 (§9.1) |
| `KAKAO_CLIENT_ID` | 카카오 콘솔의 **REST API 키**. `client_id`이자 id_token의 `aud`로 돌아오는 값 |
| `KAKAO_CLIENT_SECRET` | 카카오 콘솔 Client secret. **신규 앱은 기본 ON**이라 필수다(미전송 시 `KOE010`) |
| `GOOGLE_CLIENT_ID` | GCP OAuth 클라이언트 ID (`….apps.googleusercontent.com`) |
| `GOOGLE_CLIENT_SECRET` | GCP OAuth 클라이언트 시크릿 |
| `SESSION_SECRET` | OAuth state·nonce 서명 키(SessionMiddleware 전용). 우리 인증 세션과 무관하다 — 그건 DB 세션 테이블이다 |

로컬 웹 개발과 연결할 땐 클라이언트 포트를 고정하고(`flutter run -d chrome --web-port <포트>`) 그 origin을 `CORS_ALLOWED_ORIGINS`에 넣는다 — 포트가 랜덤이면 허용 목록이 성립하지 않는다 (§10).

## 인증 (#100)

| 라우트 | 행동 |
| --- | --- |
| `GET /api/v1/auth/{kakao\|google}/login` | IdP 인가 화면으로 302 |
| `GET /api/v1/auth/{kakao\|google}/callback` | ID 토큰 1회 검증 → 계정 upsert → 세션 발급(쿠키 + JSON) |
| `GET /api/v1/auth/me` | 현재 계정 — 세션 검증 표면 |
| `POST /api/v1/auth/logout` | 세션 행 삭제 (멱등) → 204 |
| `DELETE /api/v1/auth/account` | 탈퇴 — 계정 하드 삭제, 세션은 FK CASCADE → 204 |

세션 토큰은 쿠키(`cookmark_session`, HttpOnly·Secure·SameSite=Lax)와 `Authorization: Bearer` 양쪽으로 받는다 — 저장은 하나, 운반만 플랫폼별이다(§9). 계정은 `(id, iss, sub, created_at)`이 전부다(§12.1).

### 실 IdP 로컬 로그인 데모 — 파운더 콘솔 작업 (CI 밖)

`.env.local`의 placeholder를 아래에서 얻은 실 값으로 바꾸고 `uv run uvicorn …`으로 띄운 뒤
`http://localhost:8000/api/v1/auth/kakao/login`을 **브라우저로** 연다(Chrome 권장 — Safari는
`http://localhost`에 Secure 쿠키를 안 준다). 성공 시 콜백이 세션 JSON을 반환하고, 이어서
`http://localhost:8000/api/v1/auth/me`가 같은 계정을 보여준다.

**카카오** ([developers.kakao.com/console/app](https://developers.kakao.com/console/app))

1. 애플리케이션 추가 (개인 계정으로 충분 — Biz 앱 불필요).
2. **[앱 설정] > [플랫폼] > Web 플랫폼 등록** → 사이트 도메인 `http://localhost:8000`. 이게 있어야 Redirect URI 칸이 열린다.
3. **[제품 설정] > [카카오 로그인] > 활성화 ON**, Redirect URI에 정확히 `http://localhost:8000/api/v1/auth/kakao/callback` (정확 일치 — 불일치 시 `KOE006`).
4. **[제품 설정] > [카카오 로그인] > [OpenID Connect] ON** — 이게 없으면 `id_token`이 아예 안 나온다.
5. **[동의항목]은 전부 OFF로 둔다** — `openid`엔 동의항목이 필요 없고, 프로필·이메일을 켜면 §12.1 위반이다.
6. **[앱 키] > REST API 키** → `KAKAO_CLIENT_ID` · **[앱 키] > Client secret**(기본 ON) → `KAKAO_CLIENT_SECRET`.

**구글** ([console.cloud.google.com/apis/credentials](https://console.cloud.google.com/apis/credentials))

1. OAuth consent screen → User Type **External**, 게시 상태 Testing으로 충분.
2. **Test users에 파운더 본인 구글 계정을 추가** — Testing 모드에서 미등록 계정은 `access_denied`를 받는다.
3. Scopes는 **아무것도 추가하지 않는다**(§12.1 — 이메일·프로필 무수집).
4. Credentials → OAuth client ID → Application type **Web application**(Desktop 아님 — redirect 매칭 규칙이 다르다).
5. Authorized redirect URIs에 정확히 `http://localhost:8000/api/v1/auth/google/callback` (포트까지 정확 일치). JavaScript origins는 비워둔다.
6. Client ID/secret → `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`.

> **`redirect_uri`는 요청의 Host 헤더에서 나온다**(설정값이 아니다). 그래서 브라우저 주소가 정확히
> `http://localhost:8000`이어야 콘솔에 등록한 값과 맞는다 — `127.0.0.1:8000`으로 열면 같은 서버인데도
> 불일치로 거절당한다(카카오 `KOE006`).

> **데모에서 확인할 미결 1건** — 구글이 `scope=openid` **단독**을 받아주는지는 실 로그인으로만 확정된다(구글 문서는 최소 scope에 `profile`/`email`을 함께 적는다). 거절당하면 §12.1(무수집)과 충돌하므로 조용히 scope를 늘리지 말고 결정을 올린다.

배포(Cloud Run 서울 + Secret Manager)는 [#98](https://github.com/woosung-dev/cookmark/issues/98)의 몫이다. OpenAPI 스냅샷·드리프트 가드는 [#99](https://github.com/woosung-dev/cookmark/issues/99)로 배선됐다(위 계약 절).
