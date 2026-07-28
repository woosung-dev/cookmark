# migration 도메인 예외 — 원자적 등록이 실패했다 (티켓 #104)
#
# 영구 모듈이다 — 근거와 개명 시점은 src/migration/ __init__.py 참조.


class RecipeImportFailed(Exception):
    """bulk 등록 중 실패 — 전량 롤백됐고 저장된 행은 0이다. 부분 성공은 없다."""
