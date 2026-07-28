# 인증 비즈니스 로직 — 계정 upsert·세션 발급/검증/파기. AsyncSession도 Request도 모른다 (backend.md §3)
import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from src.auth.models import Account, AuthSession
from src.auth.repository import AccountRepository, SessionRepository

# 세션 수명 — 쿠키 Max-Age와 DB expires_at이 **발급 시점에** 같은 값에서 나온다.
# 설정 노브는 요구가 없어 만들지 않는다.
#
# **슬라이딩 도입(#167)이 이 등가를 발급 시점으로 좁혔다.** 아래 authenticate가 DB의 expires_at만
# 밀기 때문에 오래 쓰는 클라이언트에서는 쿠키가 먼저 만료되고 Bearer는 계속 산다. 원 주석은 그 갈림을
# 결함으로 적었으나 **지금은 의도다** — 슬라이딩의 소비자는 네이티브 Bearer(기기 등록)이고 쿠키는
# 웹 로컬 데모 전용이라 만료가 곧 재로그인일 뿐이다. 매 응답에 Set-Cookie를 다시 얹는 대안은
# 모든 라우트를 쿠키 발행자로 만들기 때문에 기각했다.
SESSION_TTL = timedelta(days=30)

# 익명 기기 계정의 발급자 (#167 · ADR-0012). 승격(로그인)은 이 행의 iss/sub를 실제 신원으로
# UPDATE하는 것이라 **이름이 사는 곳은 여기 하나**여야 한다.
# scripts/seed_sessions.py의 "local-seed"와 합치지 말 것 — 갈라져 있다는 것이 ADR-0012의 요점이다
# (사전프로비저닝 계정은 iss가 달라 승계가 구조적으로 불가능하다).
DEVICE_ISS = "device"


def hash_token(token: str) -> str:
    """DB엔 해시만 남긴다 — 유출된 DB·백업이 곧 세션 탈취가 되지 않게(§12.3은 PITR 잔존을 인정한다)."""
    return hashlib.sha256(token.encode()).hexdigest()


@dataclass(frozen=True)
class IssuedSession:
    token: str
    expires_at: datetime
    account: Account


class AuthService:
    def __init__(
        self, accounts: AccountRepository, sessions: SessionRepository
    ) -> None:
        self._accounts = accounts
        self._sessions = sessions

    async def login(self, iss: str, sub: str) -> IssuedSession:
        """검증된 신원을 세션으로 바꾼다. 같은 (iss, sub)면 계정을 재사용한다."""
        account = await self._accounts.get_by_identity(iss, sub)
        if account is None:
            account = await self._accounts.add(Account(iss=iss, sub=sub))

        token = secrets.token_urlsafe(32)
        expires_at = datetime.now(UTC) + SESSION_TTL
        await self._sessions.add(
            AuthSession(
                token_hash=hash_token(token),
                account_id=account.id,
                expires_at=expires_at,
            )
        )
        # 두 Repository가 같은 session을 공유하므로 조율 서비스가 마지막에 한 번만 커밋한다 (§3).
        await self._accounts.commit()
        return IssuedSession(token=token, expires_at=expires_at, account=account)

    async def register_device(self) -> IssuedSession:
        """익명 기기 계정과 세션을 함께 발급한다 — 호출할 때마다 새 계정이다 (#167).

        sub은 **서버가** 만든다(§9: 클라이언트가 계정 식별자를 대는 경로는 없다). uuid4라 login의
        계정 재사용 분기는 절대 타지 않는데, 그 SELECT 한 번을 아끼려 발급 경로를 복제하지 않는다 —
        세션 발급이 두 곳에 사는 편이 훨씬 비싸다.
        """
        return await self.login(DEVICE_ISS, str(uuid.uuid4()))

    async def authenticate(self, token: str) -> Account | None:
        """증표를 계정으로 바꾸고, 성공한 검증마다 만료를 30일 뒤로 다시 민다 (#167 · ADR-0012).

        **갱신은 조회의 만료 필터 뒤에 붙는다** — 앞에 붙으면 죽은 세션이 되살아나 로그아웃·탈퇴의
        즉시 폐기(§9)가 무력해진다. 익명 등록에서는 토큰이 계정으로 가는 유일한 링크라, 갱신이
        없으면 30일 뒤 조용한 401 → 재등록 → 새 계정 → 레시피 북 고아가 된다.

        **알려진 대가** — ADR-0012는 "UPDATE 1회"라 적었으나 실제 왕복은 **UPDATE + COMMIT 둘**이
        늘어난다(전에는 커밋 없이 풀 반납 시 ROLLBACK이었다). DB가 Neon 싱가포르라 인증된 요청마다
        ~120-140ms가 붙는다. 커밋이 커넥션을 풀에 돌려주므로 라우트 본문은 **다음 커넥션**을 잡는다
        — 코호트 규모(max-instances 3)에선 무해하나 동시성 프로필이 바뀐 것은 사실이다.
        임계값 기반 갱신(남은 수명이 절반 이하일 때만)도, 조회와 갱신을 CTE 한 문장으로 합치는 것도
        **최적화이지 결정이 아니다** — 측정된 적 없는 숫자에 선지불하지 않는다(ADR-0012 재검토
        트리거: flip 관통 스모크의 콜드·웜 지연 실측 후 필요가 드러나면).

        **갱신 실패를 삼키지 않는다** — try/except로 감싸면 읽기 라우트가 조용히 갱신 없이 성공하는
        숨은 모드가 생긴다. UPDATE를 못 받는 DB는 어차피 잠시 뒤 라우트를 죽인다.
        """
        token_hash = hash_token(token)
        now = datetime.now(UTC)
        account = await self._sessions.get_account_for_token(token_hash, now)
        if account is None:
            return None

        await self._sessions.extend_expiry(token_hash, now, now + SESSION_TTL)
        await self._sessions.commit()
        return account

    async def logout(self, token: str) -> None:
        """세션 행을 지운다 — 만료 표시가 아니라 삭제다. 즉시 폐기가 세션 채택의 근거였다(#77)."""
        await self._sessions.delete_by_token_hash(hash_token(token))
        await self._sessions.commit()

    async def withdraw(self, account: Account) -> None:
        """계정을 즉시 하드 삭제한다. 세션은 FK ON DELETE CASCADE로 함께 죽는다 (§12.3 soft delete 금지)."""
        await self._accounts.delete(account)
        await self._accounts.commit()
