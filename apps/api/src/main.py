# FastAPI 앱 조립 — CORS 허용 목록은 env 주입, 경로는 /api/v1 프리픽스 (ADR-0009 · #94)
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.core.config import get_settings
from src.health.router import router as health_router

app = FastAPI(title="cookmark-api")

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_allowed_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router, prefix="/api/v1")
