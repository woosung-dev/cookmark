# auth 도메인 예외 — IdP 왕복의 실패를 라우터가 HTTP로 옮기기 전 단계에서 하나로 모은다
class IdentityUnavailable(Exception):
    """IdP가 검증된 (iss, sub)를 주지 못했다 — 서명·nonce·state·동의 거부·응답 형식 전부 여기로 모인다."""


class ProviderNotConfigured(Exception):
    """이 서버에 해당 IdP의 자격증명이 없다 (#163 Optional 강등).

    IdentityUnavailable과 **다른 종이다** — 저건 사용자 왕복이 실패한 것이고(401), 이건 서버 설정
    결함이다(503). 둘을 한 코드로 뭉치면 운영자가 원인을 잃는다.
    provider를 str로 받는 이유 — Provider(oidc.py)를 import하면 oidc→exceptions와 순환한다.
    """

    def __init__(self, provider: str, missing: tuple[str, ...]) -> None:
        super().__init__(f"{provider} 자격증명 부재 — {', '.join(missing)} 미설정")
        self.provider = provider
        self.missing = missing
