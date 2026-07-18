# apps/api 컷오버 로컬 스모크 런북 (#121)

컷오버(#121)의 도착선은 배포가 아니라 **로컬 통합 + 스모크 관통**이다 — 앱(컷오버 빌드)이 apps/api FastAPI를 Bearer 세션으로 타고, 실 Gemini까지 한 번 뚫리는 것을 눈으로 확인한다. 이 문서는 그 절차의 정본이다. 실 Gemini 호출은 **~5회(≈$0.005)로 통제**한다 — 체크리스트의 실 호출 항목만 세면 된다.

## 1. env 병합 (가장 흔한 실패 지점)

**가장 흔한 실패 = env 미병합.** Settings 필수 필드(`DATABASE_URL`·IdP 4종·`SESSION_SECRET`·`GEMINI_API_KEY`) 중 하나라도 비면 **seed 단계부터 pydantic `ValidationError`로 죽는다**. 서버가 아니라 시드가 먼저 죽는 게 정상 신호다 — env부터 다시 본다.

```bash
cd apps/api
source /tmp/cookmark_spike_env.sh                 # 스파이크가 남긴 6종 (아래 §2에 원문)
export GEMINI_API_KEY="$(grep '^GEMINI_API_KEY=' ../../.env.local | cut -d= -f2-)"  # 루트 파일럿 키 보충
export CORS_ALLOWED_ORIGINS="http://localhost:8777"   # 컷오버 빌드 서빙 오리진
```

> ⚠️ **CORS는 앱 import 시점에 바인딩된다** — `src/main.py`가 미들웨어를 import 시 조립하므로, `CORS_ALLOWED_ORIGINS`는 **서버 기동 전에 export**돼 있어야 하고 **값을 바꾸면 uvicorn 재기동이 필수**다. 켜진 서버에 export만 하면 조용히 무시된다.

## 2. /tmp env 휘발 대비 — 재작성 절차

`/tmp/cookmark_spike_env.sh`는 재부팅에 휘발한다. 없으면 아래로 재작성한다 (IdP 4종·SESSION_SECRET은 더미로 충분 — 이 스모크는 OIDC 로그인을 타지 않는다).

```bash
cat > /tmp/cookmark_spike_env.sh <<'EOF'
export DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:5435/cookmark"
export CORS_ALLOWED_ORIGINS="http://localhost:8777"
export KAKAO_CLIENT_ID="spike-dummy"
export KAKAO_CLIENT_SECRET="spike-dummy"
export GOOGLE_CLIENT_ID="spike-dummy"
export GOOGLE_CLIENT_SECRET="spike-dummy"
export SESSION_SECRET="spike-dummy-session-secret-not-real"
EOF
```

`GEMINI_API_KEY`는 이 파일에 넣지 않는다 — §1처럼 루트 `.env.local`에서 매번 보충한다(실 키를 /tmp에 남기지 않는다).

## 3. 기동 시퀀스

§1 env 병합이 끝난 셸에서, 순서대로.

```bash
docker start cookmark-spike-pg        # 스파이크 Postgres (localhost:5435)
uv sync                               # 의존성
uv run alembic upgrade head           # 스키마 최신화
TOKEN=$(uv run python scripts/seed_sessions.py | awk 'NR==1{print $2}')   # pilot-1 토큰만 취득
uv run uvicorn src.main:app --port 8099
```

- **토큰은 stdout → 셸 변수로만 받는다. 파일 저장 금지** — 원문 평문은 DB에도 없다(해시만 저장). 유출 표면을 셸 히스토리 밖으로 늘리지 않는다.
- 시드는 멱등이다 — 재실행해도 계정 2개는 유지되고 새 토큰만 얹힌다(구 토큰도 TTL까지 유효).
- **시드 토큰 TTL은 30일** — 만료되면 위 `TOKEN=$(…)` 한 줄만 다시 돌리면 된다.

## 4. 스모크 체크리스트

curl 구간 (서버 :8099 · 실 Gemini 호출 수를 항목에 표기).

- [ ] **health 200** — `curl -s http://localhost:8099/api/v1/health` → `{"status":"ok"}`.
- [ ] **무토큰 401** — `curl -s -o /dev/null -w '%{http_code}' http://localhost:8099/api/v1/recipes` → `401`.
- [ ] **빈 목록 200** — `curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8099/api/v1/recipes` → `[]` (시드 직후 빈 계정).
- [ ] **502 + 미저장 재현** — `GEMINI_API_KEY`를 깨뜨린 셸에서 서버를 재기동하고 recipes POST → `502`, 이어서 GET 목록이 여전히 `[]`(조용한 저장 없음). 확인 후 **정상 키로 재기동**.
- [ ] **실추출 201 (실 Gemini 1회)** — `curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"url":"https://www.youtube.com/watch?v=ZsvevWrQ6M0","title":"김치찌개"}' http://localhost:8099/api/v1/recipes` → `201` + 추출 재료 동봉.
- [ ] **match 관통 (실 Gemini 1회)** — `curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"ingredients":["김치","두부","대파"],"recipes":[{"title":"김치찌개","ingredients":["김치","돼지고기","두부","대파"]}]}' http://localhost:8099/api/v1/llm/match` → `200` + `match_score` 실산출.
- [ ] **PATCH·DELETE** — `PATCH /api/v1/recipes/{id}`(`{"title":"…"}`) → `200`, `DELETE` → `204`.

브라우저 구간 (컷오버 빌드 · :8777 서빙).

```bash
cd apps/mobile
flutter build web -t lib/main_api_cutover.dart \
  --dart-define=COOKMARK_API_BASE=http://localhost:8099 \
  --dart-define=COOKMARK_SESSION_TOKEN=$TOKEN
(cd build/web && python3 -m http.server 8777)     # CORS 허용 오리진과 일치해야 한다
```

- [ ] **레시피 add 실추출 (실 Gemini 1회)** — 레시피 북에서 URL+제목 추가 → 재료가 실추출로 붙는다.
- [ ] **리스트 = 서버** — 방금 add한 항목이 `GET /api/v1/recipes`(curl)에도 보인다 — 로컬 스토리지가 아니라 서버가 진실원.
- [ ] **Network 탭** — 요청에 `Authorization: Bearer` 헤더, 본문/응답이 snake_case(`/api/v1/*`).
- [ ] **CORS 프리플라이트** — `OPTIONS`가 200으로 통과하고 본 요청이 뒤따른다(막히면 §1 CORS 재기동 확인).
- [ ] **recognize 관통 (실 Gemini 1~2회)** — `main_api_spike.dart` 빌드(동일 dart-define)로 교체 서빙 → 부팅 즉시 번들 사진 recognize → 체크리스트 렌더까지.

## 5. 토큰 취급 요약

- 발급 경로는 `scripts/seed_sessions.py` 하나 — stdout 탭 구분 3필드(iss/sub · 토큰 · 만료).
- **셸 변수로만 운반, 파일 금지.** DB에는 sha256 해시만 남는다.
- 만료(30일)·분실 시 재시드 1줄 — §3의 `TOKEN=$(…)`.
