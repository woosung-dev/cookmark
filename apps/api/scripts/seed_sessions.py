# 사전 프로비저닝 파일럿 계정 2개에 세션 토큰을 발급하는 로컬 전용 시드 (#121) — CI·프로덕션 밖 수동 전용.
#
# 사용법 (apps/api에서, Settings 필수 env 4종이 공급된 상태로 — 절차는 docs/pilot/api-cutover-smoke.md).
# 4종 = DATABASE_URL·SESSION_SECRET·GEMINI_API_KEY·COOKMARK_REGISTER_KEY. IdP 4개는 Optional이라
# 이 스크립트와 무관하다(#163). 등록 키는 이 스크립트가 쓰지 않지만 Settings 필수라 부팅에 필요하다(#167).
#
# **이 스크립트는 익명 기기 등록(POST /auth/device)의 대체재가 아니다.** iss가 갈려 있는 것이 요점이다 —
# "local-seed" 계정은 나중에 실제 로그인이 붙어도 (iss, sub)가 달라 승계가 구조적으로 불가능하다(ADR-0012).
# 코호트 배포는 등록 라우트를 쓰고, 이 시드는 파일럿 2대의 기존 토큰을 위해 남는다(#171 합류까지).
#   uv run python scripts/seed_sessions.py
# 출력은 stdout뿐 — 계정당 한 줄, 탭 구분 3필드(iss/sub · 토큰 원문 · 만료 시각).
# 파일로 남기지 않는다 — 토큰 원문은 DB에도 없다(해시만 저장, src/auth/service.py).
# 멱등 — 재실행하면 같은 (iss, sub) 계정을 재사용하고 새 토큰을 얹는다.
# 구 토큰도 폐기되지 않고 TTL(30일)까지 유효하다.
import asyncio

from src.auth.repository import AccountRepository, SessionRepository
from src.auth.service import AuthService
from src.common.database import get_engine, get_sessionmaker

SEED_ISS = "local-seed"
SEED_SUBS = ("pilot-1", "pilot-2")


async def main() -> None:
    try:
        async with get_sessionmaker()() as session:
            service = AuthService(
                AccountRepository(session), SessionRepository(session)
            )
            for sub in SEED_SUBS:
                issued = await service.login(SEED_ISS, sub)
                expires = issued.expires_at.isoformat()
                print(f"{SEED_ISS}/{sub}\t{issued.token}\t{expires}")
    finally:
        # lru_cache 엔진 풀을 루프가 살아있을 때 정리한다 — 안 하면 종료 시 asyncpg 경고가 남는다.
        await get_engine().dispose()


if __name__ == "__main__":
    asyncio.run(main())
