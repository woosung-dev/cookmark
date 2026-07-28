# #162 체크리스트 — ADR-0012 발행 + 상류 문서 정합

티켓 정본은 [#162](https://github.com/woosung-dev/cookmark/issues/162), 상류는 스펙 [#161](https://github.com/woosung-dev/cookmark/issues/161)(지도 [#153](https://github.com/woosung-dev/cookmark/issues/153) CLOSED · 인증 화해 [#156](https://github.com/woosung-dev/cookmark/issues/156) · 데이터 경계 [#159](https://github.com/woosung-dev/cookmark/issues/159) · flip 게이트 [#157](https://github.com/woosung-dev/cookmark/issues/157) · 프록시 폐기 [#160](https://github.com/woosung-dev/cookmark/issues/160)). 결정 로그는 `context-notes.md`.

목표 한 줄 — **미래의 독자가 세 가지를 리포 문서에서 정확하게 읽는다** — ① 왜 로그인 없이 서버 계정이 생기는가 ② 레시피 북의 로컬 사본은 캐시인가 미러인가 ③ Vercel 프록시를 언제 지우는가. 지금은 셋 다 문서가 없거나 거짓이다.

범위 경계 — **리포 트리 문서 + 거짓 주석**만. 살아 있는 문서 5곳의 정본 URL 은퇴 표기는 **합류 시점 티켓**이고, `backend.md` §9 포인터는 **gitignored 로컬 정본이라 파운더 몫**이다.

## 산출물

- [x] **ADR-0012 신규** — `docs/adr/0012-anonymous-device-registration.md`. §9 명시적 예외 · 신원 모양(`iss="device"`) · 등록 시크릿 · 슬라이딩 세션 · IdP 4필드 Optional 강등 · 미러 계약 · 하이드레이트 가드 · 401 재등록 · 탈퇴 UI 미노출 · 고아 잔존 §12 예외 + 파기 트리거 · 승격 트리거 4 · 쿼터 지연 트리거 3 · 발효 = flip 시점
- [x] **역전이 아니라 연기임을 명시** — 신원 필드 UPDATE = 로그인 승격 · 스키마 변경 0 · `uq_accounts_iss_sub` 그대로 성립
- [x] **슬라이딩 세션 근거를 정확히** — 소멸하는 것은 **도달 가능성이지 데이터가 아니다**(reaper 0건). "자연 소멸 = 고아 청소"는 **#156 결의문의 거짓을 #159가 정정한 이력**으로만 등장하고 주장으로는 쓰지 않는다
- [x] **ADR-0009 정정 4곳** — 최상단 정정 블록쿼트 + 인라인 중첩 주석. `:55` 미러 · `:15` 폐기 트리거(#157·#160 링크) · `:34` `COOKMARK_SERVER_BASE` 분리(이름 재사용 금지 사유 포함) · `:60` 이전 모듈 영구 승격
- [x] **ADR-0008 정정 1곳** — 두 번째 정정 블록쿼트 + `api/` 행 4열 `합류 후 단순 삭제`
- [x] **`CONTEXT.md` 주간 백업** — 집계 수집 지점 역할에 8/5 만료 표기. **보험 역할은 불변·강화**. 꼬리 괄호의 "가구 합산 수집 지점 역할은 불변" 문구가 새 서술과 모순돼 함께 정정
- [x] **이전 모듈 제거 절차 즉시 삭제** — `__init__.py` docstring 전면 재작성(영구 승격) · 5개 파일 헤더 포인터화 · `main.py` 조립부 주석 2곳 · `router.py` 네임스페이스 주석의 "제거 시" 전제
- [x] **신규 ADR은 0012 하나뿐** — 프록시 은퇴는 ADR-0009·0008 인라인 정정, ADR-0012는 한 글자도 안 적는다
- [x] 살아 있는 문서 5곳 URL 은퇴 표기 — **하지 않았다**(선 뒤 티켓)
- [x] `backend.md` §9 포인터 — **PR에 포함하지 않고 커밋 본문에 파운더 몫으로 명시**

## 검증

- [x] `uv run ruff check src/` · `ruff format --check src/` — All checks passed / 49 files formatted
- [x] `uv run mypy src/` — Success: no issues found in 49 source files
- [x] `uv run pytest -q` — **230 passed**
- [x] `uv run python scripts/export_openapi.py` → `contracts/openapi.yaml` **diff 0** (라우트·스키마 무변경 → 드리프트 가드 무영향)
- [x] `flutter analyze` — No issues found (Dart 0줄 변경 무손상 스모크)
- [x] grep 정합 — **`docs/adr/` + `apps/api/src/` 범위에서** `파일럿 종료 후`/`로컬 캐시 없음`/`시한부` 잔존이 전부 정정 주석과 짝을 이룬다(무관 ADR 0004·0010·0011 제외)
- [x] ADR-0012 AC 12항목 문구 스캔 · 트리거가 재검토 절 **한 곳에만** 열거 · 종결 콜론 0 · 이모지 0
- [x] `/code-review` — Standards·Spec 두 축. 두 축이 **같은 하드 결함 1건**을 독립 적발(ADR-0009 정정 블록쿼트의 행 번호가 삽입 전 값이라 전부 밀림 — 특히 "(13행)"이 *살아남는다고 선언한 바로 그 줄*을 가리켰다). **행 번호를 절 이름 + 인용구로 교체**해 해소. 나머지 반영은 `context-notes.md` 리뷰 반영 절
- [ ] 커밋

## 표면화 — 고치지 않은 것

- **`docs/tickets/104/context-notes.md`에 `## 제거 트리거 (시한부)` 절차가 살아 있다.** 정정 주석 없이 남아 있으나 **시점 기록이라 손대지 않았다**(ADR-0008 "기존 문서의 시점 기록은 소급 수정하지 않는다 — 살아있는 운영 문서만 고친다"). 실행 위험은 낮다(닫힌 티켓의 작업 문서이고 정본 docstring·ADR·조립부가 전부 "영구"라 말한다). **정본 3곳이 참이 된 지금도 이게 거슬리면 별도 티켓**으로 날짜 붙은 한 줄 정정을 다는 것이 관례에 맞다.
