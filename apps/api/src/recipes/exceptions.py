# recipes 도메인 예외 — 부재와 남의 것을 구분하지 않는다 (backend.md §12.2 — 존재를 노출하지 않는다)


class RecipeNotFound(Exception):
    """소유자 스코프 안에 그 레시피가 없다 — 남의 레시피도 정확히 같은 예외로 끝난다."""
