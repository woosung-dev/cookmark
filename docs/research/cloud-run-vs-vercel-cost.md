# Cloud Run 원가·콜드스타트 vs 현행 Vercel 서버리스 프록시 — apps/api flip 게이트 리서치

> wayfinder 티켓 [#154](https://github.com/woosung-dev/cookmark/issues/154)(부모 [#153](https://github.com/woosung-dev/cookmark/issues/153) · blocking [#157](https://github.com/woosung-dev/cookmark/issues/157)) · WebSearch/WebFetch + Google 공식 가격 페이지 원본 HTML 파싱 · **조회 시점 2026-07-23**
> 표기 — ✅ 1차 소스(공식 문서·공식 가격 페이지)로 확인 / ⚠️ 2차 소스 교차확인 또는 1차 소스에서 수식으로 역산한 추정치 / ❓ 이번 조사로 못 잰 값(실측 필요)
> 가격은 변한다 — 아래 숫자는 전부 2026-07-23 시점 스냅샷이다. flip 실행 직전 재확인 권장.

## 핵심 결론

1. **n=2 파일럿 트래픽 규모에서는 Cloud Run min-instances=0이든 현행 Vercel Hobby든 인프라 비용은 사실상 $0다.** 결정 변수는 비용이 아니라 **콜드스타트가 코어 루프(사진→LLM 인식 5~10초) 위에 얹혀 사용자가 체감하느냐**다.
2. **Cloud Run min-instances=1을 서울(asia-northeast3)에서 켜면 트래픽과 무관하게 월 약 $10~15가 상시 발생한다**(1 vCPU·512MiB 기준, ⚠️ Tier 2 idle 단가는 역산 추정치 — 아래 §1 참조). 파일럿 규모에선 이 비용이 콜드스타트 회피의 대가 전부다.
3. **서울(asia-northeast3)은 Cloud Run Tier 2 리전이다**(✅, Google 공식 가격 페이지 원본에서 직접 확인) — 도쿄(asia-northeast1)·오사카는 Tier 1인데 서울만 Tier 2로 분류돼 있다. Tier 1 대비 CPU·메모리 단가가 1.4배(요청기반 과금 기준, ⚠️ 자유등급 크레딧 환산으로 역산해 교차확인).
4. **n=2 파일럿의 "하루 몇 번" 트래픽 패턴에서는 콜드스타트가 예외가 아니라 사실상 기본값일 가능성이 높다** — Cloud Run은 유휴 인스턴스를 몇 분 단위로 회수하는데, 사용자가 하루 몇 차례만 쓰면 요청 간격이 그보다 길어 min-instances=0에서는 거의 매 요청이 콜드일 수 있다. 이건 "가끔 느림"이 아니라 "항상 조금 더 느림"으로 읽어야 한다.
5. **현행 Vercel 프록시(Node.js, `.mjs`)는 구조적으로 콜드스타트에 더 유리하다** — 의존성이 `fetch` 호출 하나뿐이라 임포트 그래프가 가볍고(✅), Fluid Compute의 "Active CPU"는 I/O 대기(Gemini 응답 기다리는 5~10초)를 과금하지 않는다(✅, Vercel 공식 문서). 반면 `apps/api`는 SQLAlchemy·asyncpg·alembic·authlib·google-genai를 한 컨테이너에서 임포트하는 FastAPI라 콜드스타트가 구조적으로 더 무겁다.
6. **DB 계층이 콜드스타트를 이중으로 만든다** — `backend.md` §9가 **전 라우트 세션 필수**를 못박았으므로, apps/api로 flip하면 LLM 프록시 호출조차 매번 세션 검증용 DB 왕복이 낀다. Neon Free/Launch는 5분 유휴 후 auto-suspend가 기본이라(✅), n=2 파일럿처럼 요청 간격이 긴 트래픽에서는 **API 컨테이너 콜드스타트 + DB 웨이크업이 같은 요청에 겹칠 공산이 크다.**
7. **Cloud SQL은 Neon과 달리 auto-suspend가 아예 없다** — 항상 구동만 지원하고(✅, 관리 콘솔에서 수동 stop은 가능하나 자동 wake-on-connect가 없음), 최소 구성(`db-f1-micro`, 0.6GB shared-core)조차 월 약 $9~11이 트래픽과 무관하게 고정 발생한다. 파일럿 규모에선 apps/api의 DB로 Neon을 쓰는 게 `backend.md` 표준일 뿐 아니라 비용 논리로도 명확히 우월하다.
8. **폭주 과금 방어는 두 플랫폼의 기본 설계 자체가 다르다** — Vercel Hobby는 결제수단이 없어 한도 초과 시 **요청이 그냥 막힌다**(과금 자체가 구조적으로 불가능, ✅). Cloud Run은 사용량 기반 과금이라 예산 알림(Budget Alert)은 통지일 뿐 지출을 막지 않으며(✅, Google 공식 가이드), 실제 상한을 걸려면 **`max-instances` 설정 + (선택) 자동 킬스위치 Cloud Function을 직접 구성**해야 한다. `apps/api`엔 현재 rate limiting 미들웨어가 없다(리포 확인, `apps/api/src` grep 결과 0건).

## 트래픽 가정 (명시)

- 사용자 n=2, 하루 core-loop 실행 각 사용자 최대 ~5회로 넉넉히 가정 → 하루 최대 ~10회 실행.
- core-loop 1회 = LLM 프록시 호출 최대 3건(recognize·extract·match, 스펙 #13 기준).
- **요청/일 ≈ 30건, 요청/월 ≈ 900건** — 여유를 크게 잡아 10배(요청/월 ≈ 9,000건)를 대입해도 §1·§4의 결론(사실상 $0)은 바뀌지 않는다.
- 요청 1건 평균 처리시간 ≈ 8초(티켓이 명시한 "실측 5~10초"의 중간값, LLM 업스트림 대기 포함).
- 컨테이너 구성 가정 — 1 vCPU · 512MiB(0.5 GiB) 메모리, request-based billing(기본값, "CPU는 요청 처리 중에만 할당"). instance-based billing("CPU 상시 할당")은 이 앱처럼 요청 사이 백그라운드 작업이 없으면 불필요.

## 1. Cloud Run 비용 — min-instances 0 vs 1 (서울 asia-northeast3)

### 원본 가격 (Tier 1, request-based billing) — ✅ Google 공식 [cloud.google.com/run/pricing](https://cloud.google.com/run/pricing) 원본 HTML에서 직접 파싱

| 항목 | Active(요청 처리 중) | Idle(min-instances로 유지되는 유휴 시간) |
| --- | --- | --- |
| CPU (per vCPU-second) | $0.000024 | $0.0000025 |
| Memory (per GiB-second) | $0.0000025 | $0.0000025 |
| Requests (per 1,000,000) | $0.40 | — |

- 월 무료 등급(Tier 1 기준 크레딧) — CPU 180,000 vCPU-초 · 메모리 360,000 GiB-초 · 요청 200만 건.
- "idle min instance" 요금은 **min-instances로 켜둔 인스턴스에만 적용**되고, min-instances가 아닌 유휴 인스턴스는 과금되지 않는다(✅, 페이지 각주 원문).
- 무료 등급은 **Tier 1 단가로 계산된 정액 크레딧**이다(✅, 페이지 원문: "The free tier is applied as a spending based discount using Tier 1 pricing"). 즉 Tier 2 리전에서 쓰면 크레딧 금액은 같아도 살 수 있는 vCPU-초/GiB-초 수량이 준다 — 아래 Tier 2 수치가 이 로직으로 역산된 이유다.

### 서울(asia-northeast3) = Tier 2 — ✅ Google 공식 리전 목록에서 직접 확인

Google 리전 목록 페이지([docs.cloud.google.com/run/docs/locations](https://docs.cloud.google.com/run/docs/locations))가 asia-northeast3(Seoul)을 **Tier 2**로 명시한다. 흥미로운 점 — 같은 동북아여도 도쿄(asia-northeast1)·오사카(asia-northeast2)는 **Tier 1**이고 서울만 Tier 2다.

### Tier 2 단가 (역산 추정, ⚠️)

Google 가격 페이지는 리전을 고르면 JS로 표를 다시 그리는 방식이라 원본 HTML에는 기본 리전(Tier 1) 값만 정적으로 박혀 있다. 대신 2차 소스([economize.cloud](https://www.economize.cloud/resources/gcp/pricing/cloud-run/))가 제시한 Tier 2 수치를, 위에서 확인한 "무료 등급 = Tier 1 단가로 계산된 정액 크레딧" 규칙으로 **직접 재계산해 정합성을 검증**했다.

- CPU 무료 크레딧 = 180,000 × $0.000024 = $4.32. Tier 2 단가($0.0000336/vCPU-초)로 나누면 128,571 vCPU-초 — economize.cloud가 제시한 "Tier 2 무료 등급 128,571 vCPU-초"와 정확히 일치.
- 메모리 무료 크레딧 = 360,000 × $0.0000025 = $0.90. Tier 2 단가($0.0000035/GiB-초)로 나누면 257,142 GiB-초 — 역시 정확히 일치.
- 두 계산 모두 **Tier 2/Tier 1 = 1.4배**로 수렴한다(요청기반 과금 CPU·메모리 active 단가 기준).

이 교차검증으로 **Tier 2 active 단가($0.0000336/vCPU-초, $0.0000035/GiB-초)는 신뢰도 높음(⚠️→사실상 확인)**. 단, **idle(min-instance) 단가의 Tier 2 배율은 Google 원본 페이지에서 직접 확인하지 못했다** — Tier 1에서 "idle CPU 단가 = active 메모리 단가"라는 패턴이 정확히 성립했으므로(둘 다 $0.0000025), Tier 2에서도 같은 패턴(idle CPU ≈ active 메모리 $0.0000035)이 유지된다고 가정했다. **이 부분은 순수 추정이다 — flip 직전 GCP 콘솔 견적기로 재확인 권장.**

### 계산 — min-instances=0

- 요청/월 900건(여유 있게 9,000건도 함께 표기) × 8초 × 1 vCPU = CPU 7,200~72,000 vCPU-초/월. Tier 2 무료 등급(128,571 vCPU-초/월)로 전부 커버.
- 메모리도 같은 비율로 무료 등급(257,142 GiB-초/월) 안에 전부 들어간다.
- 요청 수(900~9,000건)도 무료 등급 200만 건에 비하면 반올림 오차 수준.
- **결론 — min-instances=0, 서울 리전: 월 $0** (10배 여유를 둬도 무료 등급 안에서 소화된다).

### 계산 — min-instances=1

- 상시가동 시간 ≈ 730시간/월(GCP 관례 단위) = 2,628,000초.
- Idle CPU = 2,628,000초 × 1 vCPU × $0.0000035(추정) ≈ **$9.2**
- Idle Memory = 2,628,000초 × 0.5 GiB × $0.0000035(추정) ≈ **$4.6**
- 무료 등급을 일부 상쇄해도(위 §1 요청기반 무료 크레딧이 상시가동분 앞부분을 흡수) 큰 차이는 안 남는다 — **월 대략 $10~15로 수렴**(idle 단가 추정 오차를 감안한 범위).
- 3자 소스([oneuptime.com](https://oneuptime.com/blog/post/2026-02-17-how-to-configure-minimum-instances-on-cloud-run-to-eliminate-cold-starts-for-production-services/view) 등, 2026-02 게시)도 "1 vCPU·512MB급 min-instances=1은 월 $10 안팎"이라는 같은 자릿수를 보고해 정합성을 뒷받침한다.

## 2. 콜드스타트 지연 (min-instances=0)

- **Google 공식 정성적 가이드** — 일반적인 앱은 수백 ms~2초(⚠️, 여러 GCP 파트너·2차 자료가 일관되게 인용하는 수치지만 이번 조사에서 원문 그대로의 단일 공식 문장은 못 찾음).
- **실측 벤치마크(3자, 경쟁사 소스 — 편향 가능성 명시)** — Cloudflare가 2025-12-08 게시한 Python Workers 콜드스타트 벤치마크([developers.cloudflare.com](https://developers.cloudflare.com/changelog/2025-12-08-python-cold-start-improvements))는 `httpx`·`FastAPI`·`Pydantic`을 임포트하는 워크로드로 세 플랫폼을 계속 측정한다. 이 세 패키지는 `apps/api`의 실제 임포트 그래프와 겹친다(단, `apps/api`는 여기에 SQLAlchemy·asyncpg·alembic·authlib·google-genai가 추가로 더 얹힌다).
  - Cloud Run 평균 콜드스타트 **3,069ms**
  - AWS Lambda 평균 2,502ms
  - Cloudflare Python Workers(자사 제품) 평균 1,027ms
  - ⚠️ **주의** — Cloudflare가 자사 제품과 비교하는 벤치마크라 방법론에 유리한 조건을 골랐을 가능성을 배제 못 한다. 다만 워크로드(FastAPI 스택 임포트)가 이 앱과 실제로 겹치는 몇 안 되는 수치라 참고 가치는 있다.
- **Startup CPU boost** — Google 공식 발표(2022-09-26)는 Java에서 최대 50%, Node.js에서 최대 30% 콜드스타트 단축을 보고했지만(✅), **Python 특정 수치는 공식적으로 공개된 바 없다**(❓).
- **`apps/api`의 실제 임포트 그래프가 벤치마크보다 무겁다** — `pyproject.toml` 확인 결과 `sqlalchemy[asyncio]`·`asyncpg`·`alembic`·`authlib`·`google-genai`·`uvicorn[standard]`가 전부 부팅 시 임포트된다. 위 3,069ms는 하한으로 보는 게 안전하다.
- ❓ **이건 실측해야 한다** — `apps/api`를 실제로 Cloud Run에 배포해 `time curl`로 콜드/웜 요청을 재는 것 외에는 이 앱 고유의 정확한 숫자를 알 방법이 없다. #98(Cloud Run 프로비저닝) 완료 후 첫 배포에서 반드시 실측할 것.

### n=2 파일럿에서 콜드스타트가 "가끔"이 아닐 수 있다

Cloud Run은 트래픽이 끊기면 인스턴스를 회수한다(정확한 유휴 타임아웃은 Google이 공개하지 않고 내부 휴리스틱으로 동작 — ❓). 업계 통념은 "몇 분~십수 분 무요청 시 회수"다. n=2 파일럿의 "하루 몇 번" 요청 간격은 이보다 길기 쉽다 — 즉 **min-instances=0에서는 거의 매 요청이 콜드스타트일 수 있다.** "가끔 로딩이 길다"가 아니라 "매번 로딩이 1~3초 더 길다"로 설계 전제를 잡아야 한다.

### 체감 여부 판단

- 웜 상태 기준 요청: LLM 인식만으로 5~10초.
- 콜드 상태 기준 요청(위 3,069ms 벤치마크 + Neon 웨이크업 §4): 최악의 경우 **총 7~15초**.
- 5~10초짜리 로딩 위에 1~3초가 더 얹히는 건 **비율로는 15~30% 증가**다 — 이미 로딩 스피너가 뜨는 흐름이라 "고장"으로 오인될 위험은 낮지만, 체감상 "느리다"는 인상은 분명히 강화된다. 정확히 몇 초를 사용자가 "차이를 느끼는 경계"로 잡는지는 **이번 조사 범위 밖(제품 판단)**.

## 3. 현행 Vercel 서버리스 프록시와 비교

### 현황 확인 (리포 실측)

- `api/recognize.mjs`·`api/extract.mjs`·`api/match.mjs` — Node.js 서버리스 함수, 공용 `api/_gemini.mjs`만 의존. **임포트 그래프가 사실상 없다**(런타임 fetch 호출 하나).
- `vercel.json`은 `git.deploymentEnabled.main: false`로 자동배포를 막아뒀고 별도 Pro/Hobby 플랜 명시는 리포에 없다 — 이번 조사에선 **Hobby 요금제로 가정**(파일럿 규모에 Pro를 쓸 이유가 없다는 §5 결론과도 일치). ❓ 실제 플랜은 Vercel 대시보드에서 확인 필요.

### Vercel Hobby 요금 — ✅ [vercel.com/pricing](https://vercel.com/pricing), [vercel.com/docs/fluid-compute](https://vercel.com/docs/fluid-compute)

| 항목 | Hobby 포함량 | 초과 시 |
| --- | --- | --- |
| Active CPU | 4시간/월 | **과금 없음 — 한도 도달 시 요청 자체가 막힌다**(결제수단 없음) |
| Provisioned Memory | 360 GB-시간/월 | 상동 |
| Function Invocations | 1,000,000/월 | 상동 |

- **Fluid Compute의 "Active CPU"는 I/O 대기를 과금하지 않는다**(✅, 공식 문서 원문: "Waiting for I/O (e.g. calling AI models, database queries) does not count towards active CPU time"). 이 프록시의 요청 처리 8초 중 대부분은 Gemini 응답을 기다리는 I/O 대기라, **실제 청구 대상 Active CPU는 요청당 수십~수백 ms에 불과할 가능성이 높다.**
- Provisioned Memory는 벽시계 시간 전체 × 메모리로 과금되므로 I/O 대기도 포함된다. 계산 — 요청/월 900건 × 8초 × 2GiB(Hobby 기본) = 14,400 GiB-초 ≈ 4 GB-시간/월. 360 GB-시간 한도의 1%대. 10배 트래픽(9,000건)을 가정해도 40 GB-시간대로 여전히 여유.
- **결론 — Vercel Hobby, n=2 파일럿: 월 $0, 구조적으로 초과 과금이 불가능하다(카드 자체가 없음).**

### Vercel 콜드스타트

- 공식 주장(2025-09-18 블로그, [vercel.com/blog/scale-to-one-how-fluid-solves-cold-starts](https://vercel.com/blog/scale-to-one-how-fluid-solves-cold-starts)) — "요청의 99.37%는 콜드스타트가 없다"(✅, 원문 인용). 단, 이 통계는 Vercel 전체 트래픽 평균으로 보이며, 인스턴스를 계속 웜하게 유지할 만큼 트래픽이 잦은 앱들이 평균을 끌어올렸을 공산이 크다 — **n=2 파일럿처럼 요청이 뜸한 경우 이 99.37%가 그대로 적용된다고 보기 어렵다**(⚠️, Cloud Run과 동일한 논리적 함정).
- 구체적 ms 수치는 공식 문서에서 못 찾음(❓). 다만 **Node 함수는 임포트 그래프가 얇아서(§ 위 "현황 확인") 콜드스타트가 나더라도 FastAPI+SQLAlchemy 스택보다 구조적으로 짧을 가능성이 높다** — 정량 비교는 실측 없이는 확정할 수 없다.

## 4. DB 상시 비용

### Neon (backend.md 표준) — ✅ [neon.com/pricing](https://neon.com/pricing)

| 플랜 | 컴퓨트 | 스토리지 | Auto-suspend |
| --- | --- | --- | --- |
| Free | 100 CU-시간/월/프로젝트 | 0.5GB | **5분 유휴 후 자동**(고정, 끌 수 없음) |
| Launch | $0.106/CU-시간(정액 없음, 사용한 만큼) | $0.35/GB/월 | 5분 유휴 후 자동(끌 수 있음) |
| Scale | $0.222/CU-시간 | $0.35/GB/월 | 1분~상시 구동 사이 설정 가능 |

- n=2 파일럿 트래픽(§ 트래픽 가정)이면 세션 검증·레시피북 CRUD를 다 합쳐도 실제 컴퓨트 가동 시간은 하루 몇 분 수준 — **Free 플랜 100 CU-시간/월(0.25CU 기준 약 400시간 상당)로 넉넉히 커버**. **결론 — 월 $0.**
- **Auto-suspend 웨이크업 지연** — Neon 공식 문서([neon.com/docs/connect/connection-latency](https://neon.com/docs/connect/connection-latency))는 "유휴 상태에서 컴퓨트를 깨우는 데 보통 수백 ms가 걸린다"고만 서술하고 정확한 ms·백분위수는 공개하지 않는다(✅ 정성적 확인, 정량 수치는 ❓). 실측 벤치마크 사이트(neon-latency-benchmarks.vercel.app)를 직접 열어봤으나 **실제 데이터 없이 placeholder(0ms)만 표시돼 있어 신뢰할 수 없다** — 이번 조사에서 폐기.
- **정직한 결론 — Neon 웨이크업 지연의 정확한 수치는 실측해야 한다.** 공식 문서가 제시하는 정성적 범위("수백 ms")를 최선의 추정치로 쓰되, 실제 배포 후 첫 콜드 쿼리를 재는 걸 권장.

### Cloud SQL for PostgreSQL — ✅ [cloud.google.com/sql/pricing](https://cloud.google.com/sql/pricing) 원본 HTML에서 직접 파싱

| 인스턴스 | vCPU | RAM | 시간당 단가 |
| --- | --- | --- | --- |
| db-f1-micro | Shared | 0.6 GiB | $0.0105 |
| db-g1-small | Shared | 1.7 GiB | $0.035 |

- ❓ 이 값은 페이지 기본 표시 리전(문서상 명시 없음, 통상 us-central1로 추정) 기준이다 — Cloud Run과 달리 Cloud SQL의 서울 리전 정확한 배율은 이번 조사로 확인하지 못했다. 다만 GCP 리전 프리미엄이 통상 10~40% 범위인 걸 감안하면 큰 방향은 바뀌지 않는다.
- db-f1-micro 상시가동 월 비용 ≈ 730시간 × $0.0105 = **$7.67** + 최소 스토리지(10GB SSD, GB당 월 ~$0.17) ≈ **$1.70** → **합계 약 $9~11/월**(3자 소스 2건이 같은 자릿수로 교차확인, 2026 게시).
- **Cloud SQL은 auto-suspend 자체가 없다** — 수동으로 인스턴스를 멈출 수는 있지만(그래도 스토리지 요금은 계속 나감) 연결이 오면 자동으로 깨는 기능이 없다. 즉 트래픽이 0이어도 상시 $9~11/월이 고정 발생하고, 반대로 "무활동 지연"이라는 개념 자체가 없다(항상 켜져 있으니).
- **결론 — 파일럿 규모에선 Neon Free($0)가 Cloud SQL 최소구성($9~11/월 고정)보다 명백히 유리하다.** `backend.md`가 이미 Neon을 표준으로 못박은 것과 방향이 일치한다.

### 세션 필수 설계가 만드는 복합 지연

`backend.md` §9는 전 라우트 세션 검증을 요구한다. 이 말은 **LLM 프록시 호출도 매번 최소 1회 DB 왕복(세션 조회)을 거친다**는 뜻이다. n=2 파일럿처럼 요청 간격이 길면 Neon도 자주 suspend 상태일 가능성이 높고, 그러면 **"API 컨테이너 콜드스타트(§2) + DB 웨이크업(§4) + LLM 호출(5~10초)"이 한 요청에 다 겹치는 게 드문 일이 아니라 파일럿 기간 내내 반복될 기본 패턴일 수 있다.** 최악의 경우 총 체감 지연 ≈ 7~15초 (§2 재인용).

## 5. 폭주 과금 실패 모드 · 킬 스위치

### 두 플랫폼의 방어선이 근본적으로 다르다

- **Vercel Hobby** — 결제수단이 등록돼 있지 않다. 한도 초과 시 **초과 과금이 아니라 서비스 정지**로 처리된다(✅). 구조적으로 "예상 밖의 청구서"가 나올 수 없다 — 대신 파일럿 도중 한도를 넘으면 앱이 그냥 멈춘다는 다른 리스크가 생긴다.
- **Cloud Run(pay-as-you-go)** — 결제수단이 필수고 사용량 기반 과금이라 상한이 기본으로 없다. Google 공식 가이드([cloud.google.com/blog](https://cloud.google.com/blog/products/serverless/managing-cost-and-reliability-serverless-applications))는 **예산 알림(Budget Alert)이 지출을 막지 않고 통지만 한다**는 점을 명시한다(✅). 실제 상한을 걸려면 아래 두 가지가 필요하다.
  1. **`max-instances` 설정** — 동시 인스턴스 수 상한이 곧 최악의 경우 비용 상한이다. Google이 1차 방어선으로 명시 권장(✅). n=2 파일럿엔 낮게(2~3) 잡아도 충분.
  2. **자동 킬스위치** — 예산 알림을 Pub/Sub로 받아 Cloud Function이 프로젝트 결제를 자동으로 끄는 패턴이 커뮤니티에 문서화돼 있다(⚠️, 2차 소스 — "Automated GCP Killswitch" 계열 글). 기본 제공 기능이 아니라 **직접 구성해야 한다.**

### 이 앱에 실제로 있을 법한 시나리오

1. **재시도 폭주(클라이언트 버그·네트워크 불안정)** — LLM 프록시 호출이 무한 재시도되면 Cloud Run 요청당 5~10초 wall time이 그대로 CPU/메모리 과금 단위가 되고, **Gemini 토큰 비용이 Cloud Run 인프라 비용보다 먼저, 더 크게 뛴다.** 현재 원가 산식(T1 #6, `api/_gemini.mjs` 주석 기준 실측 $0.0011~0.002/루프)으로 역산하면 재시도 수천 건이면 하루 만에 수 달러~수십 달러 단위로 튈 수 있다 — Cloud Run 자체보다 **LLM 토큰 과금이 진짜 리스크**라는 점을 flip 결정에 반영할 필요가 있다.
2. **무인증 라우트 남용** — `backend.md` §9가 전 라우트 세션을 요구하므로 apps/api로 flip하면 이 표면 자체가 원칙적으로 사라진다(현재 Vercel 프록시가 무인증이라는 게 오히려 지금의 리스크다). 단, Cloud Run 자체는 `--allow-unauthenticated`로 열어야 브라우저가 직접 호출 가능하므로, **Cloud Run IAM 레벨 과금 방지("인증 실패 요청은 과금 안 됨", ✅ 공식 문서)는 이 앱엔 적용되지 않는다** — 세션 없는 요청도 컨테이너까지 도달해 짧게라도 CPU/메모리를 태운다(앱 레벨 401 응답 자체는 빠르므로 단가는 작다).
3. **DB 측 연쇄 과금** — 위 재시도 폭주가 그대로 세션 조회 DB 호출도 반복시키므로 Neon Free/Launch CU-시간도 같이 소모된다. 무료 등급을 넘으면 Launch 종량제로 넘어가지만(정액 없음), 단가 자체가 크지 않아 Cloud Run·LLM 쪽 리스크에 비하면 부차적이다.
4. **현재 방어막 상태** — `apps/api/src`를 grep한 결과 **rate limiting/throttle 미들웨어가 없다**(리포 실측, 이번 세션). flip 전에 최소한 `max-instances` + 세션당/사용자당 LLM 호출 빈도 제한 중 하나는 채워 넣는 걸 권장한다.

## 못 잰 것 (정직한 목록)

- **Cloud Run Tier 2(서울) idle 단가의 정확한 승수** — active 단가는 무료등급 크레딧 역산으로 교차확인했지만(⚠️→사실상 확인), idle 단가는 Tier 1의 "idle CPU = active 메모리" 패턴을 그대로 가정한 추정이다. GCP 콘솔 견적기로 재확인 권장.
- **`apps/api`를 실제로 Cloud Run에 배포했을 때의 콜드스타트 ms** — Cloudflare 3자 벤치마크(FastAPI+httpx+pydantic만 임포트)는 하한으로 보되, SQLAlchemy·asyncpg·alembic·authlib·google-genai가 추가된 이 앱의 실제 컨테이너는 이보다 느릴 가능성이 높다. #98 배포 후 실측 필수.
- **Neon auto-suspend 웨이크업의 정확한 ms·백분위수** — 공식 문서는 "수백 ms"라는 정성적 표현만 제공한다. 실측 벤치마크 사이트를 확인했으나 데이터가 비어 있어 폐기했다.
- **Cloud SQL 서울 리전의 정확한 리전 프리미엄** — 가격 페이지가 리전 선택 드롭다운으로 동적 렌더링돼 원본 HTML엔 기본 리전 값만 정적으로 박혀 있었다. 방향(고정비 $9~11/월 근방)은 신뢰할 만하나 소수점까지는 확인 못 함.
- **현재 Vercel 프로젝트가 실제로 Fluid Compute를 쓰고 있는지, Hobby인지 Pro인지** — 리포 안에서는 확인할 수 없다(대시보드 설정). 2025-04-23 이후 신규 프로젝트 기본값이 Fluid Compute이고 이 프로젝트가 그 이후 생성된 걸로 보이므로 켜져 있다고 가정했지만, 확정은 아니다.

## 이 숫자가 결정에 어떻게 쓰이나

- **비용은 flip을 막는 이유가 못 된다.** min-instances=0 Cloud Run과 현행 Vercel Hobby 둘 다 n=2 파일럿 트래픽에서 월 $0에 수렴한다(10배 여유를 둬도 마찬가지). DB도 Neon Free로 $0. **"원가 상한을 넘어서 flip을 미룬다"는 시나리오는 이번 조사 범위에서 현실성이 낮다** — 유일하게 상시비용이 생기는 선택지는 min-instances=1($10~15/월)이나, 이건 선택이지 강제가 아니다.
- **진짜 결정 변수는 지연이다.** min-instances=0을 택하면 콜드스타트(Cloud Run) + DB 웨이크업(Neon)이 겹쳐 최악의 경우 LLM 호출 5~10초 위에 추가로 2~5초가 얹힐 수 있고, n=2 파일럿의 뜸한 트래픽 패턴상 이게 "가끔"이 아니라 "거의 매번"일 수 있다. **flip 게이트가 물어야 할 질문은 "월 $10~15를 써서 min-instances=1로 이 지연을 없앨 가치가 있느냐"이지, "Cloud Run이 감당 가능한 비용이냐"가 아니다.** 파일럿 예산 규모(개인 프로젝트)에서 $10~15/월은 결정을 좌우할 금액이 아니므로, 실질적으로는 **"체감 지연을 감수하고 $0으로 갈지, $10~15로 없앨지"의 단순한 선택**으로 좁혀진다.
- **Vercel 프록시 폐기 시점은 이 리서치가 아니라 실측이 가른다.** 현재 프록시(Node, 얇은 의존성)가 구조적으로 콜드스타트에 유리하다는 정성적 근거는 있지만, `apps/api`를 실제로 붙여보기 전엔 정량 비교가 불가능하다 — #98 배포 직후 첫 실측(콜드/웜 각각 `time curl`)을 flip 여부 확정의 필수 게이트로 남겨둘 것을 권한다.
- **폭주 과금 방어는 flip과 별개로 지금 채워야 할 갭이다.** Cloud Run으로 넘어가면 Vercel Hobby의 "카드가 없어 구조적으로 못 초과한다"는 안전망이 사라진다. flip 실행 전 `max-instances` 설정과 최소한의 요청 빈도 제한(현재 0건)을 함께 티켓화할 것을 제안한다 — 이건 비용 문제라기보다 **LLM 토큰 과금이 실제 리스크의 대부분을 차지한다**(§5-1)는 걸 감안하면 인프라보다 앱 레벨 가드가 우선순위다.

## 출처

[Cloud Run 가격](https://cloud.google.com/run/pricing) · [Cloud Run 리전/Tier 목록](https://docs.cloud.google.com/run/docs/locations) · [Cloud Run 최소 인스턴스 설정](https://docs.cloud.google.com/run/docs/configuring/min-instances) · [Cloud Run 최대 인스턴스 설정](https://docs.cloud.google.com/run/docs/configuring/max-instances) · [GCP 서버리스 비용·안정성 관리 공식 블로그](https://cloud.google.com/blog/products/serverless/managing-cost-and-reliability-serverless-applications) · [Startup CPU boost 발표](https://cloud.google.com/blog/products/serverless/announcing-startup-cpu-boost-for-cloud-run--cloud-functions) · [economize.cloud Cloud Run 가격 요약(2차 소스, Tier 2 교차확인용)](https://www.economize.cloud/resources/gcp/pricing/cloud-run/) · [oneuptime.com min-instances 콜드스타트 가이드(2026-02)](https://oneuptime.com/blog/post/2026-02-17-how-to-configure-minimum-instances-on-cloud-run-to-eliminate-cold-starts-for-production-services/view) · [Cloudflare Python Workers 콜드스타트 벤치마크(2025-12-08)](https://developers.cloudflare.com/changelog/2025-12-08-python-cold-start-improvements) · [davidmuraya.com FastAPI on Cloud Run 튜닝(2025-09-04)](https://davidmuraya.com/blog/fastapi-performance-tuning-on-google-cloud-run/) · [Vercel 가격](https://vercel.com/pricing) · [Vercel Functions 한도](https://vercel.com/docs/functions/limitations) · [Vercel Fluid Compute](https://vercel.com/docs/fluid-compute) · [Vercel "Scale to one" 콜드스타트 블로그(2025-09-18)](https://vercel.com/blog/scale-to-one-how-fluid-solves-cold-starts) · [Vercel Python 런타임](https://vercel.com/docs/functions/runtimes/python) · [Neon 가격](https://neon.com/pricing) · [Neon 연결 지연 문서](https://neon.com/docs/connect/connection-latency) · [Cloud SQL 가격](https://cloud.google.com/sql/pricing) · [Neon 실측 벤치마크 대시보드(데이터 비어있어 폐기)](https://neon-latency-benchmarks.vercel.app/)
