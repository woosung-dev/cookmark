# ogimage용 SSRF 가드 표면 — 판정 로직은 src/common/urlguard.py로 이동했고(#123) 여기는 re-export다
"""공개 표면·기존 테스트 호환을 위한 위임 계층.

- 판정식·이월 사항의 정본 주석은 src/common/urlguard.py에 있다.
- ensure_public_url은 공용 가드 예외를 ogimage 도메인 예외로 번역한다(라우터 400 계약 유지).
- resolve_host를 이 모듈 이름으로 다시 내보내는 이유 — 기존 테스트가 guard.resolve_host를
  monkeypatch한다. 아래 위임이 호출 시점에 이 모듈 전역을 조회하므로 그 seam이 유지된다.
"""

from src.common import urlguard
from src.common.urlguard import (  # noqa: F401 — re-export (공개 표면 유지)
    ALLOWED_SCHEMES,
    is_public_address,
    resolve_host,
)
from src.ogimage.exceptions import OgImageBlocked, OgImageUnresolvable

# 명시적 재수출 — mypy(no_implicit_reexport)와 공개 표면 선언을 겸한다
__all__ = ["ALLOWED_SCHEMES", "ensure_public_url", "is_public_address", "resolve_host"]


async def ensure_public_url(url: str) -> None:
    """비공개 대상이면 OgImageBlocked, 미해석이면 OgImageUnresolvable — 기존 계약 그대로."""
    try:
        # resolver로 이 모듈 전역의 resolve_host를 넘긴다 — monkeypatch(guard.resolve_host)가 살아있는 이유.
        await urlguard.ensure_public_url(url, resolver=lambda host: resolve_host(host))
    except urlguard.UrlBlocked as exc:
        raise OgImageBlocked(url) from exc
    except urlguard.UrlUnresolvable as exc:
        raise OgImageUnresolvable(str(exc)) from exc
