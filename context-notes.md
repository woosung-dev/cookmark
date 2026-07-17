# Context Notes — #97 api-1 스캐폴드 + 검증 하네스

자율결정 감사 추적. 결정/근거 1줄씩 append. 계획: `~/.claude/plans/97-dazzling-manatee.md`.

## 스코프 경계 (착수 전 확정)

- **#97 = 로컬 절반만.** Dockerfile·Cloud Run·WIF·Secret Manager는 #98, OpenAPI 스냅샷·드리프트 가드는 #99 — 이 PR에 넣지 않는다.
- 루트 `api/`(.mjs 프록시)·`vercel.json`·`apps/mobile` 무접촉 (파일럿 가드 ~8/5).

## 결정 로그

- **health = DB 미접촉 liveness** — DATABASE_URL이 죽은 값이어도 uvicorn이 뜨게(engine lazy). DB 관통 증명은 테스트가 담당(SELECT 1 + alembic_version 존재). readiness 분리는 #98에서 필요 시.
- **`allow_credentials` 미설정(기본 False)** — 쿠키 세션은 #100의 몫. §10 함정(credentials+wildcard 불법)은 와일드카드 금지로 이미 차단되지만, 선지불 안 함.
- **빈 베이스라인 리비전 1개** — 모델이 아직 없다(#100·#103). `upgrade head`가 alembic_version 테이블을 실 DB에 쓰는 것으로 파이프라인을 증명.
- **Python 3.13 핀** — asyncpg·SQLModel 호환 확인된 현행 안정판. 시스템 3.14에 기대지 않고 `.python-version`으로 고정.
- **테스트의 URL 주입 경로 = env var** — Settings가 env_file보다 실제 env var를 우선하므로, conftest가 `DATABASE_URL`을 컨테이너 URL로 설정하고 settings 캐시를 클리어한다. dependency override 없음(스펙 "코드 우회 없음"과 정합).
- **CORS 콤마 파싱** — pydantic-settings `list[str]`는 JSON 선-디코드라 콤마 값이 크래시(§10 실측 선례) → `NoDecode` + validator.

## 구현 중 발견·결정 (append)

- **greenlet 명시 의존(`sqlalchemy[asyncio]`)** — macOS arm64는 sqlalchemy의 greenlet 플랫폼 마커 밖이라 asyncio 사용 시 미설치 크래시. 실측 후 추가.
- **E501 제외** — 한국어 주석은 문자 수 기준이 실폭과 안 맞는다. 코드 줄 길이는 `ruff format`이 보장.
- **isort `known-third-party = ["alembic"]`** — 로컬 `alembic/` 디렉토리 때문에 설치 패키지가 first-party로 오분류되는 것 방지.
- **pytest-asyncio 세션 단일 루프** — engine 풀 커넥션이 테스트 간 다른 루프로 재사용되는 asyncpg 폭발 방지(후속 티켓 DB 테스트 대비 하네스 차원 선결).
- **수동 확인은 8090 포트** — 로컬 8000이 딴 프로세스에 점유돼 있었음. 코드 기본값과 무관(uvicorn 인자).
- **브라우저 실검증 증거** — 허용 origin(5566) `FETCH_OK {"status":"ok"}` · 비허용 origin(7777) `FETCH_BLOCKED Failed to fetch` + preflight curl 200/400 교차 확인.
