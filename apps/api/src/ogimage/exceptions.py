# og:image 도메인 예외 — 정책 위반(차단)과 fetch 실패(부재)를 라우터가 구분하는 경계
class OgImageBlocked(Exception):
    """SSRF 정책 위반 — 사설·루프백 등 비공개 대상, 비 http(s) 스킴, userinfo. 라우터에서 400."""


class OgImageUnresolvable(Exception):
    """호스트가 해석되지 않음 — 정책 위반이 아니라 fetch 실패다. 서비스에서 부재(null)로 흡수."""
