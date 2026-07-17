# FastAPI 앱 조립 — CORS 허용 목록은 env 주입, 경로는 /api/v1 프리픽스 (ADR-0009 · #94)
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.sessions import SessionMiddleware

from src.auth.router import router as auth_router
from src.core.config import get_settings
from src.health.router import router as health_router

# OAuth state·nonce의 수명 — 인가 화면에 머무는 시간이면 충분하다. 우리 인증 세션(30일)과 무관하다.
OAUTH_STATE_TTL_SECONDS = 600

app = FastAPI(title="cookmark-api")

# 이 세션은 authlib의 OAuth state·nonce를 로그인 시작→콜백 사이에 나르는 서명 쿠키 전용이고,
# 우리 인증 세션이 아니다 — 그건 DB 세션 테이블 + 불투명 토큰이다 (backend.md §9).
app.add_middleware(
    SessionMiddleware,
    secret_key=get_settings().session_secret.get_secret_value(),
    max_age=OAUTH_STATE_TTL_SECONDS,
    same_site="lax",
    https_only=True,
)

# CORS를 마지막에 얹는다 — 나중에 추가한 미들웨어가 바깥이라, 안쪽에서 난 에러 응답에도 헤더가 붙는다.
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_allowed_origins,
    # 쿠키 세션이 cross-origin(로컬 웹 → 로컬 API)으로 실려야 한다. 와일드카드와 이 조합은 스펙상
    # 불법이라 §9.1의 "명시 origin 목록"이 여기서 강제된다 — Settings가 "*"를 거부한다.
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router, prefix="/api/v1")
app.include_router(auth_router, prefix="/api/v1")
