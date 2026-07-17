# syntax=docker/dockerfile:1
# ↑ 반드시 1행이어야 BuildKit이 프론트엔드를 고정한다 — 다른 줄로 밀리면 조용히 무시된다.
#   프론트엔드만 핀하는 것이지 BuildKit을 켜지는 않는다. RUN --mount은 BuildKit에서만 도는데
#   GitHub Actions의 buildx·로컬 docker 29가 기본 BuildKit이라 충족된다.

# 냉파 백엔드 컨테이너 — uv 멀티스테이지. 내부 포트 8000 고정·non-root (backend.md §10 · ADR-0009)
#
# 빌드 컨텍스트는 반드시 apps/api다.  docker build -f apps/api/Dockerfile apps/api
# 리포 루트를 컨텍스트로 주면 아래 --mount=type=bind의 source가 컨텍스트 기준이라 pyproject.toml을 못 찾고 깨진다.

# 빌더 — uv 배포판 이미지. 태그를 uv버전-python-베이스로 완전 고정한다.
# 함정: 흔히 쓰는 python3.13-bookworm-slim 태그는 uv 0.9.30(2026-02)에 얼어붙어 있다. 현행 베이스는 trixie다.
FROM ghcr.io/astral-sh/uv:0.11.29-python3.13-trixie-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# 의존성만 먼저 — 소스는 자주 바뀌고 의존성은 거의 안 바뀐다. 레이어 캐시를 위해 분리한다.
# uv.lock·pyproject.toml은 bind 마운트라 레이어를 만들지 않는다(내용 해시만 캐시 키가 된다).
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project

COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked

# 런타임 — 파이썬 마이너 버전은 빌더와 반드시 같아야 한다(3.13). 어긋나면 venv가 통째로 안 보인다.
FROM python:3.13-slim-trixie

RUN groupadd --system --gid 999 nonroot \
    && useradd --system --gid 999 --uid 999 --create-home nonroot

# /app 통째 복사 — .venv만 복사하면 안 된다.
# uv sync는 프로젝트를 editable로 깔아서 venv 안엔 소스가 없다(.pth만 있다).
# 게다가 alembic/·alembic.ini는 src/ 밖이라 wheel에도 안 들어간다 — 통째 복사가 둘을 한 번에 푼다.
COPY --from=builder --chown=nonroot:nonroot /app /app

ENV PATH="/app/.venv/bin:$PATH"
WORKDIR /app
USER nonroot

# 포트 8000 고정 (backend.md §10). Cloud Run에는 --port=8000으로 배포한다 —
# 그 플래그가 $PORT=8000도 같이 세팅하므로 컨테이너 고정값과 런타임 주입값이 구조적으로 일치한다.
# ${PORT:-8000}로 쓰지 않는 이유: --port를 빠뜨리면 Cloud Run이 8080을 주입하는데,
# 그러면 조용히 8080을 듣게 돼 "내부 8000 고정" 규약이 깨진 채로 잘 도는 것처럼 보인다. 고정값은 시끄럽게 깨진다.
EXPOSE 8000

# exec 형식 — uvicorn이 PID 1이 되어 Cloud Run의 SIGTERM을 직접 받는다(scale-to-zero 시 graceful shutdown).
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
