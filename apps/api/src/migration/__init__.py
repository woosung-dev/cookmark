"""로컬→계정 데이터 이전 (bulk 가져오기) — 시한부 모듈 (티켓 #104 · ADR-0009 데이터 이전 절).

⚠️ 이 모듈 전체가 시한부다. 대상은 파일럿 가구 2명이고, 서버 정본 체제에선 사용자당 평생 1회
발화한다. **두 계정의 이전이 모두 완료되면 이 모듈을 제거한다.**

제거 절차:
  1. `rm -rf apps/api/src/migration/`
  2. `apps/api/src/main.py`에서 migration_router include 1줄 삭제
  3. `apps/api/tests/test_recipes_import.py` 삭제
  4. `cd apps/api && uv run python scripts/export_openapi.py` (스냅샷 재생성) 후 커밋

recipes 도메인(영구 코드)은 이 모듈에 의존하지 않는다(단방향 의존) — 제거해도 무영향이다.
"""
