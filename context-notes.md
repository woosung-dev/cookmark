# Context Notes — #99 api-3 계약 스냅샷 + CI 드리프트 가드

자율결정 감사 추적. 결정/근거 1줄씩 append.

## 스코프 경계 (착수 전 확정)

- **#99 = 계약 발행 + 가드만.** 새 라우트·모델은 #100 이후다. 현 라우트는 `/api/v1/health` 1개뿐이고, 이 티켓의 산출물은 **그 1개를 위한 계약이 아니라 이후 전 라우트가 올라탈 배선**이다.
- **하류 클라이언트 생성기(ts·dart)는 배선하지 않는다** — ADR-0009 계약 절이 트리거 미충족으로 미채택 확정. `packages/api-client-*`는 좌표로 남는다.
- 루트 `api/`(.mjs 프록시)·`vercel.json`·`apps/mobile` 무접촉 (파일럿 가드 ~8/5).

## 착수 전 실측 (통념 검증)

- **FastAPI OpenAPI 출력은 프로세스 간 결정적이다 — 단 그 이유가 통념과 다르다.** `fastapi/openapi/utils.py`가 `for method in route.methods:`로 **set**을 순회하고 문자열 해시는 프로세스마다 랜덤(`hash('GET')` 4회 실측 전부 상이)이라 순회 순서는 실제로 매번 다르다. 그럼에도 출력이 동일한 것은 최종 스키마가 Pydantic `OpenAPI` 모델을 거쳐 직렬화되고 `PathItem`의 **필드 선언 순서**(`get, put, post, delete, options, head, patch, trace`)가 순서를 정규화하기 때문이다. 5-메서드 라우트로 8개 프로세스 실측 → stdout 8/8 동일(`get,put,post,delete,patch` = 선언 순서), 반면 같은 런의 경고 출력 순서는 매번 달랐다(= set 순회는 실제로 흔들린다).
  - **따라서 `sort_keys=True` 강제 정규화는 불필요**하고, 쓰면 OpenAPI 자연 순서(`openapi`→`info`→`paths`)가 알파벳순으로 깨져 diff 가독성만 잃는다. `sort_keys=False`로 FastAPI 정규 순서를 보존한다.
  - **단 이 결정성은 FastAPI의 직렬화 구현 세부에 기댄다** — 그래서 AC를 테스트로 못박는다(별도 프로세스 2개 + 상이한 `PYTHONHASHSEED`로 재생성 → 동일).

## 결정 로그

- **스크립트 위치 = `apps/api/scripts/` (앱 패키지 `src/` 밖).** 후보였던 `src/contract.py`는 mypy·ruff 게이트가 공짜로 덮는 이점이 있으나, **`pyyaml`을 프로덕션 의존성으로 승격**시킨다(#98 Docker 이미지에 빌드타임 전용 도구의 런타임 의존이 들어감). 도구는 배포물 밖에 두고 `pyyaml`·`types-PyYAML`은 dev 그룹에 남긴다. 대가로 mypy 대상에 `scripts/`를 추가한다(새 코드를 기존 게이트 밖에 두지 않기 위해).
- **`--check`는 git이 아니라 스크립트가 판정한다.** 후보였던 `재생성 후 git diff --exit-code`는 코드가 0줄이지만, 실패 시 사람에게 **무엇을 하라는지 말하지 못한다**. `--check`는 unified diff + 재생성 명령을 함께 뱉는다. `ruff format --check`·`dart format --set-exit-if-changed`(mobile.yml)와 같은 형태이고 ADR-0009가 요구한 "모바일 포맷 게이트와 동형"에 정확히 부합한다.
- **`DATABASE_URL` 자리표시자를 `render()`가 채운다.** `main.py`가 import 시점에 `get_settings()`를 호출(CORS)하므로 앱 import에 `DATABASE_URL`이 필요하다. 스냅샷은 **설정과 무관한 코드의 순수 함수**(CORS 목록은 미들웨어이지 스키마가 아니다)이므로, 미설정 환경(CI·fresh clone)에서도 **재생성이 1명령**이도록 `os.environ.setdefault`로 자리표시자만 채운다. DB 연결은 일어나지 않는다. import는 그 뒤에 와야 해서 함수 안에서 한다 — `conftest.py`의 기존 관용구(`client` 픽스처 안 `from src.main import app`)와 동형이고 E402도 피한다.
- **YAML 헤더 2줄(생성물·재생성 명령)을 렌더에 포함**한다 — README의 "수기 수정 금지"가 파일을 여는 사람 눈앞에 있어야 실효가 있다. 헤더도 diff 대상이라 가드가 함께 지킨다.
- **`yaml.safe_dump(width=...)` 미지정** — 현 스키마엔 접히는 긴 스칼라가 없다. 기본 width 80은 향후 긴 `description`이 들어오면 줄바꿈이 재배치되며 diff를 시끄럽게 만들 수 있다(이 티켓의 목적이 diff 가시성이므로 실발현 시 조정). 지금 선지불하지 않는다.

## 구현 중 발견·결정 (append)

- **`test_contract.py`가 기존 CORS 테스트를 CI에서만 깨뜨리는 지뢰를 밟았고, 그 원인을 고쳤다.** `main.py`는 **import 시점에** `allow_origins`를 CORS 미들웨어에 바인딩한다 — 그래서 앱을 **가장 먼저 import한 테스트**가 CORS 설정을 굳혀버린다. 기존 conftest는 `CORS_ALLOWED_ORIGINS`를 세션 픽스처 **안에서** 넣었는데, 그 픽스처를 요구하지 않는 `test_contract`(알파벳순으로 `test_cors`보다 앞)가 먼저 앱을 import하면서 빈 목록으로 굳었다.
  - **로컬에선 초록이라 안 보였다** — gitignored `.env.local`의 `CORS_ALLOWED_ORIGINS=http://localhost:5566`이 conftest의 `ALLOWED_ORIGIN`과 **우연히 같은 값**이라 env_file이 대신 채워줬기 때문이다. `.env.local`을 치우고 돌리자(=CI 조건) `test_cors` 2건 즉시 실패. 실측으로만 잡히는 종류다.
  - **고침 = `os.environ[...]`를 conftest 모듈 스코프로 이동**(1줄). conftest는 테스트 모듈보다 먼저 import되므로 어떤 테스트가 앱을 먼저 import하든 값이 이미 박혀 있다. `.env.local` 유무 양쪽에서 12/12 green 재확인.
  - `DATABASE_URL`은 컨테이너 URL을 픽스처가 알아야 해서 그대로 둔다 — 앱 import엔 아무 값이나 있으면 되고(`render()`의 자리표시자) 픽스처가 실 URL로 덮고 캐시를 클리어한다.
- **schemathesis는 실 서버에 물린다 — 인프로세스 ASGI가 `backend.md` §10 금지에 정면으로 걸리기 때문이다.** v4의 ASGI 경로는 `starlette-testclient`(하드 의존)이고 이는 이름만 닮은 게 아니라 **금지 대상인 sync `TestClient` 그 자체**다(요청마다 blocking portal로 새 이벤트 루프 — asyncpg 풀에 최대로 적대적). v4 CLI는 `--app`을 아예 제거해서 인프로세스 선택지도 없다. `st run ../../contracts/openapi.yaml --url <live>`로 확정 — **발행된 계약을 실 소켓에 물리는** 형태라 발행 지점 의미와도 맞는다. 로컬 실측 green(1/1 operation, 9 케이스, Coverage+Fuzzing).
  - 대안이던 "pytest + httpx ASGITransport + `case.validate_response(resp)`"는 금지를 피하면서 인루프로 돌지만, 요청 직렬화를 수기로 하고 `suppress_health_check`·준공개 API에 기대야 해서 기각했다(#100+에서 인루프 fuzzing이 실요구가 되면 재검토).
- **드리프트 판정이 pytest와 CI 스텝 양쪽에 있는 건 의도다.** `test_committed_snapshot_is_in_sync`는 **인루프**(`uv run pytest`로 push 전에 잡힘), `--check` 스텝은 ADR-0009가 요구한 **게이트**(실패 시 unified diff + 재생성 명령을 뱉는다). mobile.md의 인루프/게이트 구분과 동형이고, 중복 비용은 2줄이다.
- **schemathesis 스텝은 드리프트 가드와 겹치지 않는다** — 가드는 `스냅샷 == 코드`를, schemathesis는 `구현 == 계약`(실 응답이 스키마를 지키는지)을 본다. 전자가 green이어도 후자는 깨질 수 있다.

## CI 실측에서 나온 함정 2건 (둘 다 로컬·추론으로는 안 잡혔다)

- **`uv run`으로 띄운 백그라운드 서버가 uv 캐시 락을 쥔 채 남아 job을 죽인다.** run 29583009480은 **본 스텝 10/10 전량 통과하고도 job이 failure**였다 — `Post Run setup-uv`의 `uv cache prune --ci`가 `Cache is currently in-use, waiting for other uv processes to finish` → `Timeout (300s) when waiting for lock` → exit 2. 살아 있던 uv 프로세스는 정리 안 한 `uv run uvicorn` 하나뿐이었다.
  - **본 스텝이 전부 초록인데 job이 빨간불**이라 원인이 스텝 로그에 없다 — post-job 로그를 열어야만 보인다. 스텝 결과만 보면 "왜 실패했는지 모르겠다"로 끝난다.
  - 고침 = 스텝 종료 시 `trap`으로 서버 kill + 출력을 `/tmp` 로그로 분리(백그라운드 프로세스가 스텝 stdout을 붙드는 별개 문제 예방). 수정 후 run 29583465512 13/13 green으로 실증.
  - **`apps/api` CI에서 서버·워커를 백그라운드로 띄우는 후속 티켓(#98 Docker 스모크 등)은 같은 지뢰를 밟는다** — `uv run ... &`를 정리 없이 남기지 말 것.
- **PR `paths` 필터에 `contracts/**`가 빠져 있었다** — 전체 diff가 `contracts/`뿐인 PR(= 머지 후 누군가 발행된 계약을 수기로 고치는 독립 PR)은 워크플로가 **아예 트리거되지 않아** 가드가 돌지 않는다. README가 "직접 고치면 CI가 막는다"고 약속하는 바로 그 경로였다. 코드리뷰 Spec 축 지적으로 발견 — **가드를 만들면서 가드가 실행될 조건을 안 본** 전형적 사각이다.
  - **`pull_request`의 `paths`는 커밋 델타가 아니라 PR 전체 diff 기준으로 평가된다**(실측 — 루트 `checklist.md`·`context-notes.md`만 바꾼 커밋 `c0d6108`이 run 29583778891을 트리거했다. 그 커밋 자체는 어떤 필터에도 안 걸리는데 PR 누적 diff에 `apps/api/**`가 있기 때문이다). `push`(main 백스톱)는 필터가 없어 무관하다.

## AC 실증 (CI run)

- **green 기준선** — run 29583465512, 13/13 success(`계약 스냅샷`·`schemathesis` 포함).
- **AC "스키마 변경 + 스냅샷 미갱신 → 빨간불"** — run 29583581654 failure. `계약 스냅샷 (드리프트 = 실패)`에서 멎고 이후 스텝 skip. 로그에 unified diff(`-summary: Health` / `+summary: …`) + `계약 스냅샷이 코드와 어긋났다. 로컬에서 재생성해 커밋할 것.` + 재생성 명령이 그대로 나온다.
- **수기 수정된 계약도 가드가 잡는다** — `openapi.yaml`만 수기로 고친 커밋에서 run 29583667756 failure(같은 스텝).
- **`contracts/**` 트리거 자체는 이 PR에서 실증되지 않았다 — 실증이 불가능하다.** 위 함정 절의 실측대로 `pull_request`의 `paths`는 **PR 전체 diff** 기준이라, 이 PR은 이미 `apps/api/**`를 포함해 무엇을 커밋하든 트리거된다. 즉 run 29583667756이 돈 것은 `contracts/**` 때문이 **아니다**(그게 없어도 돌았다). 필터가 실제로 값을 하는 건 **PR 전체가 `contracts/`만 건드릴 때**이고, 그 PR은 `contracts/openapi.yaml`이 main에 존재한 뒤에야(= 이 PR 머지 후) 만들 수 있다. **근거는 추론 + GitHub 시맨틱 실측이지 이 PR의 red/green이 아니다** — 구분해서 기록해 둔다.
- 실증 커밋 2개는 증거 확보 후 브랜치에서 제거했다(run 기록은 영구). 브랜치 히스토리는 실제 변경만 남긴다.
