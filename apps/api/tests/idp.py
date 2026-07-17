# 테스트용 가짜 OIDC IdP — 카카오·구글 실 URL을 트랜스포트 레벨로 가로챈다 (스펙 #96: 페이크 주입 seam ② 아웃바운드 HTTP 경계)
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import parse_qs, urlparse

import httpx
import respx
from joserfc import jwt
from joserfc.jwk import RSAKey

from src.auth.oidc import PROVIDERS, Provider

# 테스트 서명 키 1개를 모듈 수명으로 재사용 — RSA 생성이 테스트마다 돌면 느리다.
SIGNING_KEY = RSAKey.generate_key(2048, parameters={"kid": "test-key"})
# 서명은 맞지만 IdP의 것이 아닌 키 — ID 토큰 검증이 실제로 도는지 반증하는 데 쓴다.
IMPOSTOR_KEY = RSAKey.generate_key(2048, parameters={"kid": "test-key"})

# conftest가 env로 주입하는 값과 같아야 한다 — id_token의 aud가 client_id와 일치해야 검증을 통과한다.
CLIENT_IDS = {
    Provider.KAKAO: "test-kakao-client",
    Provider.GOOGLE: "test-google-client",
}


@dataclass(frozen=True)
class _Pending:
    """authorize 리다이렉트에서 뽑아낸, 토큰 교환 때 되돌려줘야 할 값."""

    provider: Provider
    nonce: str
    sub: str
    key: RSAKey


class FakeIdp:
    """discovery·JWKS·토큰 엔드포인트를 서빙한다. 인가 화면은 테스트가 대신한다(브라우저가 없다)."""

    def __init__(self, router: respx.Router) -> None:
        self._router = router
        self._pending: dict[str, _Pending] = {}

        for config in PROVIDERS.values():
            issuer = config.issuer
            router.get(f"{issuer}/.well-known/openid-configuration").respond(
                json={
                    "issuer": issuer,
                    "authorization_endpoint": f"{issuer}/oauth/authorize",
                    "token_endpoint": f"{issuer}/oauth/token",
                    "jwks_uri": f"{issuer}/.well-known/jwks.json",
                    "response_types_supported": ["code"],
                    "subject_types_supported": ["public"],
                    "id_token_signing_alg_values_supported": ["RS256"],
                }
            )
            router.get(f"{issuer}/.well-known/jwks.json").respond(
                json={"keys": [SIGNING_KEY.as_dict(private=False)]}
            )
            router.post(f"{issuer}/oauth/token").mock(side_effect=self._exchange_token)

    def _exchange_token(self, request: httpx.Request) -> httpx.Response:
        body = parse_qs(request.content.decode())
        pending = self._pending[body["code"][0]]
        return httpx.Response(
            200,
            json={
                "access_token": "fake-access-token",
                "token_type": "Bearer",
                "expires_in": 3600,
                "id_token": self._sign_id_token(pending),
            },
        )

    def _sign_id_token(self, pending: _Pending) -> str:
        now = int(time.time())
        claims: dict[str, Any] = {
            "iss": PROVIDERS[pending.provider].issuer,
            "sub": pending.sub,
            "aud": CLIENT_IDS[pending.provider],
            "exp": now + 300,
            "iat": now,
            "nonce": pending.nonce,
        }
        return jwt.encode({"alg": "RS256", "kid": "test-key"}, claims, pending.key)

    async def login(
        self,
        client: httpx.AsyncClient,
        provider: Provider,
        *,
        sub: str,
        key: RSAKey | None = None,
    ) -> httpx.Response:
        """로그인 시작 → (인가 화면 생략) → 콜백까지 앱을 관통한다. 반환은 콜백 응답."""
        started = await client.get(f"/api/v1/auth/{provider.value}/login")
        assert started.status_code == 302, started.text

        query = parse_qs(urlparse(started.headers["location"]).query)
        # nonce·state는 앱이 만들어 IdP로 보낸 값이다 — IdP 역할인 우리가 그대로 되돌려줘야 검증을 통과한다.
        code = f"code-for-{query['state'][0]}"
        self._pending[code] = _Pending(
            provider=provider,
            nonce=query["nonce"][0],
            sub=sub,
            key=key or SIGNING_KEY,
        )
        return await client.get(
            f"/api/v1/auth/{provider.value}/callback",
            params={"code": code, "state": query["state"][0]},
        )
