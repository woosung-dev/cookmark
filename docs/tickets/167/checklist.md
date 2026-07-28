# #167 체크리스트 — `POST /auth/device` 익명 기기 등록 + 슬라이딩 세션 + 배포 시크릿 확장

티켓 정본은 [#167](https://github.com/woosung-dev/cookmark/issues/167), 상류는 스펙 [#161](https://github.com/woosung-dev/cookmark/issues/161)(지도 [#153](https://github.com/woosung-dev/cookmark/issues/153) CLOSED)이고 결정 정본은 [ADR-0012](../../adr/0012-anonymous-device-registration.md). 결정 로그는 `context-notes.md`.

목표 한 줄 — **등록 키를 든 요청이 익명 계정과 세션을 받고, 그 토큰으로 LLM·레시피 북 라우트가 200을 낸다. 한 빌드가 N개의 계정을 만든다.**

범위 경계 — 서버(`apps/api`) + CI/배포 배선 + 문서. **앱(Dart) 0줄**([#168](https://github.com/woosung-dev/cookmark/issues/168)의 몫)이고 **신규 seam 0개**다.

## 파운더 확정 계약

- [x] 등록 키 운반 = **`Authorization: Bearer <등록 키>`**, 본문 없는 POST
- [x] 거부 코드 = **403** (재시도로 못 고치는 거부 · 401이면 #168의 "401 → 재등록"과 겹쳐 루프)
- [x] 등록 응답에 **세션 쿠키를 붙이지 않는다** (선언된 소비자는 네이티브 Bearer 하나)

## 산출물

- [x] **`POST /api/v1/auth/device`** — 익명 계정 `(iss="device", sub=<서버 발급 uuid4>)` + 세션. 응답은 **기존 `SessionResponse` 재사용**(새 계약 표면 0). `DEVICE_ISS` 상수는 `src/auth/service.py` 한 곳에만 산다(승격 = 그 행의 iss/sub UPDATE)
- [x] **호출마다 다른 계정** — `register_device()`가 매번 새 uuid4를 만든다. 1빌드=N계정
- [x] **`COOKMARK_REGISTER_KEY` 필수 설정** — `Field(validation_alias=...)`로 접두사 env명 고정(같은 값이 APK dart-define으로도 산다). **공백 거부 validator**로 빈 키 부팅 차단(#163의 함정 — 빈 키를 인정하면 헤더 없는 요청이 매치돼 등록이 통째로 열린다)
- [x] **`require_register_key`** — 라우트 레벨 의존성이라 세션 조립보다 먼저 돌고 **DB를 만지기 전에** 거부한다. 쿠키 폴백 없음. **bytes로 비교**(§함정 1)
- [x] **슬라이딩 세션** — `SESSION_TTL` 숫자 무변경, `authenticate` 성공 시 `extend_expiry`. 만료 필터 **뒤에** 붙어 죽은 세션이 안 되살아나고, `extend_expiry`의 WHERE에도 `expires_at > now`를 들려 **문장 하나만 봐도** 그게 참이다
- [x] **알려진 대가를 코드에 남겼다** — ADR의 "UPDATE 1회"를 정정해 **UPDATE + COMMIT 둘**(~120-140ms)이라 적고, 커밋이 커넥션을 풀에 돌려주는 2차 효과까지. 임계값 갱신·CTE 합치기는 **최적화이지 결정이 아님**을 명시
- [x] **쿠키 Max-Age ↔ DB expires_at 등가가 발급 시점으로 좁혀졌다** — `service.py`의 원 주석이 그 갈림을 결함으로 적고 있었으므로 **의도로 정정**(슬라이딩 소비자는 Bearer, 쿠키는 웹 로컬 데모 전용). 매 응답 Set-Cookie 재발행 대안은 기각 사유와 함께 기록
- [x] **배포 워크플로** — 시크릿 넷을 Secret Manager에서 조회해 **서빙(`--set-secrets`)과 마이그레이션(`docker run -e`) 양쪽에** 주입. `id: dbsecret` → `id: secrets` 개명. schemathesis env에 등록 키 자리표시자(값을 남다르게 — 우연히 맞으면 죽은 DB를 때린다)
- [x] **`infra/README` 시크릿 인벤토리** — 1 → **4** + 이름/env/용도 표. §3 트립와이어 **전면 재작성**(카카오/구글 client secret을 부팅 필수로 적던 게 #163 이후 거짓) · 각 비밀에 **두 SA** `secretAccessor` 필요 명시 · §0.5 하드닝의 러너 blast radius가 1 → 4로 커졌음을 표면화
- [x] **`apps/api/README`** — env 표 + "부팅 셋 → 넷" + 인증 라우트 표에 device 행 + 슬라이딩·`expires_at` 참고값 서술 + 로컬 fuzzing 재현 명령 정정
- [x] **낡아진 참조 정정** — `scripts/seed_sessions.py` 헤더("3종 → 4종" + local-seed와 device를 합치지 말 것) · `docs/pilot/api-cutover-smoke.md` 필수 필드 목록·heredoc
- [x] **계약 스냅샷 재생성·커밋** — `contracts/openapi.yaml`에 device 라우트(헤더 파라미터 + 403 문서화)
- [ ] 레이트 리밋·계정당 쿼터 — **만들지 않았다**(위협 모델 = 스캐너. 지연 트리거 3건이 발화하면 그때)
- [ ] 자동 reaper · 임계값 갱신 · 앱 변경 — **범위 밖**

## 검증

- [x] `uv run ruff format --check .` · `uv run ruff check .` — All checks passed
- [x] `uv run mypy src/ scripts/` — Success: no issues found in 52 source files
- [x] `uv run pytest -q` — **253 passed** (기존 239 + 신규 14). 실 Postgres(testcontainers) 관통, 신규 seam 0
- [x] **슬라이딩이 기존 테스트를 안 깼다** — 의존성 단계의 중간 커밋이 하류 레포지토리 트랜잭션을 깨는지가 최대 리스크였고, 전량 green으로 닫았다(탈퇴·bulk import 원자성·502 미저장 포함)
- [x] `uv run python scripts/export_openapi.py --check` — 드리프트 0
- [x] **계약 fuzzing 국소 재현** — 자리표시자 DB로 실 서버 기동 후 `st run` → **1937 케이스 전량 pass**, `POST /api/v1/auth/device` 포함. `--exclude-path-regex`는 `login$` 그대로(넓힐 필요 없음이 실측으로 확인됐다)
- [x] `secrets.compare_digest`의 비-ASCII TypeError를 인터프리터로 직접 확인 — 회귀 가드가 실물임을 증명
- [x] `/code-review` — Standards·Spec 두 축. **하드 결함 0**, 반영 4건 · 표면화 4건
  - **Standards** — 문서화된 표준 위반 0. 반영: ① `extract_session_token`이 `_bearer_value`를 재사용해 Bearer 파싱 중복 제거(폴백 의미차는 `if` 위치가 지킨다) ② `SESSION_SECRET_NAME`만 `_NAME`이 붙는 이유를 주석화(**통일하면 `--set-secrets`가 시크릿 이름 자리에 값을 흘린다**)
  - **Spec** — AC 전량 충족 확인. 반영: ③ **LLM 라우트를 관통 테스트에 넣었다** — 티켓 헤드라인이 "LLM·레시피 북"인데 `/auth/me`+`/recipes`만 쳤다. 세션 필수로 닫혀 있던 비용 표면이 정확히 LLM 셋이라 빼놓을 자리가 아니다 ④ **latin-1/UTF-8 코덱 비대칭** — Starlette은 헤더를 latin-1로 디코드하는데 UTF-8로 되감고 있었다. 비-ASCII 키가 **영원히 불일치**한다(파운더가 base64 키를 쓰라는 지시 덕에 잠복). 되감기를 latin-1로 고치고 `infra/README`에 ASCII 생성을 명시
  - **ADR-0012 정정 1곳** — *"UPDATE 1회 · ~60-70ms"* 가 구현으로 거짓이 됐다(UPDATE + COMMIT · ~120-140ms + 커넥션 재획득). 중첩 정정 블록쿼트로 남겼다 — **결정은 안 흔들렸고 숫자만 커졌으며**, 그 숫자가 임계값 트리거의 판단 재료다
- [ ] 커밋

## 표면화 — 고치지 않은 것

- **`apps/api/.env.local`(gitignored)은 여전히 `DATABASE_URL`·`CORS_ALLOWED_ORIGINS` 둘뿐이다.** 등록 키만 넣어도 `SESSION_SECRET`·`GEMINI_API_KEY`가 없어 로컬 `uvicorn`·`alembic`은 그대로 죽는다 — **이 티켓 이전부터 그랬고**(#100·#101이 필수 필드를 늘렸다) 값이 개발자별이라 리포가 정할 수 없다. 절차 정본은 `docs/pilot/api-cutover-smoke.md` §1·§2다.
- **`--set-secrets`의 `:latest`는 도는 인스턴스를 안 바꾼다.** 등록 키는 유출 시 회전이 대응 수단이라 이 성질이 처음으로 실요구에 닿는다 — `api.yml` 주석에 "versions add → **새 리비전 배포** → 새 APK"가 한 묶음임을 남겼다. 숫자 버전 핀으로의 전환은 여전히 트리거 대기다.
- **`session_secret`·`gemini_api_key`에는 공백 거부 가드가 없다.** 등록 키에만 달았다 — 빈 등록 키는 **조용히 등록을 여는** 보안 구멍이고, 빈 세션 키·Gemini 키는 각각 약한 서명 키와 시끄러운 인증 실패라 등급이 다르다. 다만 **이 티켓이 그 둘을 처음으로 Secret Manager 바인딩에 태웠으므로** 빈 값이 도달 가능해진 것도 사실이다. 셋에 공통 가드를 다는 건 5줄이지만 티켓 AC 밖이라 **파운더 판단으로 남긴다**.
- **부팅 필수 env 목록이 7곳 이상에 흩어져 있다** — `config.py`·`conftest.py`·`test_config.REQUIRED_ENV`·`test_idp_optional.py`·`export_openapi.py`·`api.yml`(3곳)·README 2곳·런북. 다음 비밀이 또 전부를 반복한다. **단일 출처로 묶지 않았다** — 가장 싼 통합(`export_openapi.py` ↔ `conftest.py` 자리표시자)조차 `scripts/`가 `tests/`를 import하게 만들어 방향이 틀린다. `infra/README`가 "각 티켓이 자기 비밀을 추가한다"를 관례로 못박고 있으므로 지금은 관례를 따랐다.
- **`POST /auth/device`는 201이 아니라 200이다.** 계정이라는 자원이 생기므로 201이 더 정확하나, ADR-0012가 **로그인 콜백과 같은 응답**을 요구하고 그쪽이 200이다. 두 세션 발급 라우트가 같은 모양이어야 #168이 응답 핸들러를 하나로 쓴다. 201은 관례상 `Location`을 요구하는데 계정에는 가리킬 라우트가 없다.
- **`GET /auth/me`는 만료 시각을 노출하지 않는다.** 슬라이딩 이후 `SessionResponse.expires_at`이 발급 시점 값으로 낡으므로 클라이언트가 만료를 조회할 방법이 없다 — **의도다**(401이 신호다, ADR-0012). 필요해지면 #168이 발견할 몫이다.
