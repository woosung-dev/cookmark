# #102 api-6 og:image 프록시 — 체크리스트

티켓 정본은 [#102](https://github.com/woosung-dev/cookmark/issues/102), 상류는 스펙 [#96](https://github.com/woosung-dev/cookmark/issues/96) + ADR-0009 1기 범위 절(그릴링 [#75](https://github.com/woosung-dev/cookmark/issues/75) 이월 2건). 선행 #97(스캐폴드)·#100(인증) 머지 완료. 계획 전문은 세션 플랜 파일, 결정 로그는 context-notes.md.

## 구현

- [ ] 작업 문서(checklist·context-notes) — #102로 갱신
- [ ] `apps/api/pyproject.toml` — httpx를 `[project].dependencies`로 이동(dev 그룹 제거) + `uv lock` 재생성
- [ ] `src/ogimage/parser.py` — og:image 추출(HTMLParser, property/name 허용) — 유닛 테스트 선행(TDD)
- [ ] `src/ogimage/guard.py` — SSRF 가드(`is_global` + multicast/reserved 보강 · IPv4-mapped 언랩 · 대괄호 IPv6 · userinfo 거부 · getaddrinfo 전 주소 검사) — 유닛 테스트 선행
- [ ] `src/ogimage/service.py` — 수동 리다이렉트 루프(≤5, hop마다 가드+scheme 재검사) · 스트리밍 1 MiB 상한 · incremental 디코딩 · `asyncio.timeout(10)` 전체 데드라인
- [ ] `src/ogimage/{schemas,exceptions,router}.py` + `main.py` 등록 — GET `/api/v1/og-image?url=`, 401/400 문서화
- [ ] `src/auth/` — `UNAUTHORIZED` 상수를 dependencies.py로 이동(도메인 횡단 import 해소, 계약 무변경)
- [ ] `contracts/openapi.yaml` 재생성 커밋

## AC 검증 (tests/test_og_image.py)

- [ ] og:image 있는 페이지 → 이미지 URL 반환 (mock — respx 전용 `pages` fixture)
- [ ] og:image 없음·비HTML·fetch 실패(연결·upstream 5xx) → 200 `{"image_url": null}`, 500 아님
- [ ] 사설 IP·localhost 직접(리터럴 7종 parametrize + 사설 resolve 호스트네임) → 400 + fetch 0건 증거
- [ ] 리다이렉트 경유 사설 대상 → 400
- [ ] 타임아웃 → null · 응답 크기 상한(상한 밖 og:image → null, 상한 안 → 발견)
- [ ] 무세션 → 401 (+ 로그인 상태 쓰레기 URL → 422)
- [ ] 계약 가드 green — 스냅샷 갱신 포함(`export_openapi.py --check`)

## 마무리

- [ ] 인루프 게이트 — `pytest` · `ruff format --check` · `ruff check` · `mypy src/ scripts/` · 스냅샷 `--check` 전부 green
- [ ] schemathesis 로컬 1회(플레이스홀더 env + uvicorn 8090 — 로컬 8000 상시 점유)
- [ ] `/code-review` 2축(Standards·Spec) → 지적 반영
- [ ] 시맨틱 커밋 → `push worktree-feat-w-102:feat/102-og-image-proxy` → PR → CI green
