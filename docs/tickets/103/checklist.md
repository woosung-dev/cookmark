# #103 체크리스트 — 서버 레시피 북 CRUD

계획 정본: 세션 플랜 파일(승인됨). AC 원문은 이슈 #103.

- [x] LLM seam — 최초 `src/services/ai_processing.py`(extract 전용)로 선점 → **머지 시 #101(PR #110)의 `src/llm/` seam으로 단일화**(늦은 머지 조정 결정 이행). recipes는 `src/llm/{service,dependencies,exceptions}` 소비, 페이크는 `tests/llm.py`의 `fake_llm` 픽스처
- [x] recipes 모델 + env.py import + 마이그레이션 손작성(`198c2d418234`, FK CASCADE) — test_migrations red→green
- [x] CRUD TDD — test_recipes_crud 19건 red→green (스코프드 도메인 구현: schemas→repository→service→dependencies→router→main)
- [x] 격리 — 교차 테넌트 GET/PATCH/DELETE 404(부재 404와 응답 동일)·목록 소유자만·inspect 구조 확인
- [x] 탈퇴 CASCADE — 실 DB에서 레시피 행 0 증명
- [x] 계약 — export placeholder GEMINI_API_KEY + 스냅샷 재생성(+211줄) + test_contract green
- [x] CI — api.yml schemathesis env에 GEMINI_API_KEY placeholder
- [x] 문서 — apps/api README(env 표·레시피 북 절·배포 트립와이어), infra/README §3 주(#103 갱신, 시크릿 1→5)
- [x] 풀 게이트 — ruff format --check · ruff check · mypy · export --check · pytest -v 전량 green
- [x] /code-review → 지적 반영
- [x] PR 발행 — [#111](https://github.com/woosung-dev/cookmark/pull/111) (feat/103-recipe-book, #101 선점 관계 본문 명시)
