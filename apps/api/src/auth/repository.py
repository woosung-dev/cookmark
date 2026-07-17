# auth DB 접근 전담 — AsyncSession의 유일 보유자다. commit은 서비스 요청으로만 (backend.md §3)
from datetime import datetime

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlmodel import col

from src.auth.models import Account, AuthSession


class AccountRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_identity(self, iss: str, sub: str) -> Account | None:
        result = await self._session.execute(
            select(Account).where(col(Account.iss) == iss, col(Account.sub) == sub)
        )
        return result.scalar_one_or_none()

    async def add(self, account: Account) -> Account:
        self._session.add(account)
        # flush로 INSERT 순서를 고정한다 — 세션 행의 FK가 이 행을 참조하는데, Relationship이 없어서
        # SQLAlchemy는 두 테이블의 의존을 모른다.
        await self._session.flush()
        return account

    async def delete(self, account: Account) -> None:
        await self._session.delete(account)

    async def commit(self) -> None:
        await self._session.commit()


class SessionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, auth_session: AuthSession) -> AuthSession:
        self._session.add(auth_session)
        await self._session.flush()
        return auth_session

    async def get_account_for_token(
        self, token_hash: str, now: datetime
    ) -> Account | None:
        """세션 조회와 계정 조회를 조인 1회로 합친다 — 인증된 요청마다 도는 경로이고,
        DB가 싱가포르라 왕복 1번이 ~60-70ms다(ADR-0009 인프라 절).
        """
        result = await self._session.execute(
            select(Account)
            .join(AuthSession, col(AuthSession.account_id) == col(Account.id))
            .where(
                col(AuthSession.token_hash) == token_hash,
                col(AuthSession.expires_at) > now,
            )
        )
        return result.scalar_one_or_none()

    async def delete_by_token_hash(self, token_hash: str) -> None:
        await self._session.execute(
            delete(AuthSession).where(col(AuthSession.token_hash) == token_hash)
        )

    async def commit(self) -> None:
        await self._session.commit()
