# 인증 비즈니스 로직 — 계정 upsert·세션 발급/검증/파기. AsyncSession도 Request도 모른다 (backend.md §3)
import hashlib
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from src.auth.models import Account, AuthSession
from src.auth.repository import AccountRepository, SessionRepository

# 세션 수명 — 쿠키 Max-Age와 DB expires_at이 같은 값에서 나온다. 둘이 갈리면 쿠키만 만료되고
# 토큰은 Bearer로 영원히 살아남는다. 설정 노브는 요구가 없어 만들지 않는다.
SESSION_TTL = timedelta(days=30)


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

    async def authenticate(self, token: str) -> Account | None:
        return await self._sessions.get_account_for_token(
            hash_token(token), datetime.now(UTC)
        )

    async def logout(self, token: str) -> None:
        """세션 행을 지운다 — 만료 표시가 아니라 삭제다. 즉시 폐기가 세션 채택의 근거였다(#77)."""
        await self._sessions.delete_by_token_hash(hash_token(token))
        await self._sessions.commit()

    async def withdraw(self, account: Account) -> None:
        """계정을 즉시 하드 삭제한다. 세션은 FK ON DELETE CASCADE로 함께 죽는다 (§12.3 soft delete 금지)."""
        await self._accounts.delete(account)
        await self._accounts.commit()
