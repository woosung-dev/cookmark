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
uv run mypy src/               # 타입 (strict + pydantic 플러그인)
uv run pytest                  # 통합(ASGI + testcontainers 실 Postgres — Docker 필요) + 유닛
uv run alembic upgrade head    # 마이그레이션 적용 (--sql로 dry-run)
```

CI는 `.github/workflows/api.yml`이 매 PR(`apps/api/**` paths 필터)·main push(무필터 백스톱)에서 위 게이트를 강제한다.

## 설정 — 로컬 정본은 `.env.local` (gitignored)

| 변수 | 설명 |
| --- | --- |
| `DATABASE_URL` | `postgresql+asyncpg://…` — SecretStr. Neon PgBouncer 대비 `statement_cache_size=0`은 코드가 강제 |
| `CORS_ALLOWED_ORIGINS` | 콤마 구분 허용 origin. **기본 빈 목록** — 필요한 환경에서만 켠다. 와일드카드·regex·하드코딩 금지 (§9.1) |

로컬 웹 개발과 연결할 땐 클라이언트 포트를 고정하고(`flutter run -d chrome --web-port <포트>`) 그 origin을 `CORS_ALLOWED_ORIGINS`에 넣는다 — 포트가 랜덤이면 허용 목록이 성립하지 않는다 (§10).

배포(Cloud Run 서울 + Secret Manager)는 [#98](https://github.com/woosung-dev/cookmark/issues/98), OpenAPI 스냅샷·드리프트 가드는 [#99](https://github.com/woosung-dev/cookmark/issues/99)의 몫이다.
