# auth 도메인 예외 — IdP 왕복의 실패를 라우터가 HTTP로 옮기기 전 단계에서 하나로 모은다
class IdentityUnavailable(Exception):
    """IdP가 검증된 (iss, sub)를 주지 못했다 — 서명·nonce·state·동의 거부·응답 형식 전부 여기로 모인다."""
