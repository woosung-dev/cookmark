# FastAPI 배포 옵션 2026 현황 — Vercel 프록시와의 공존

> wayfinder 티켓 [#82](https://github.com/woosung-dev/cookmark/issues/82) · WebSearch/WebFetch 1라운드 조사 · 2026-07-17
> 표기 — ✅ 1차 소스로 확인 / ⚠️ 2차 소스 교차확인(1차 소스 접근은 실패했거나 콘텐츠가 길어 일부만 확인)
> 컨텍스트 — `.claude/rules/backend.md`는 FastAPI+SQLModel+Neon+uv를 표준으로 규정하며 Docker 배포·`asyncpg`·`AsyncSession`을 전제한다. 현재 배포된 파일럿은 정적 Flutter Web 빌드 + `api/`(Vercel Node 서버리스 함수 3개 — `recognize.mjs`·`extract.mjs`·`match.mjs`, 공용 `_gemini.mjs`)이며 `vercel.json`은 `/api/`가 아닌 모든 경로를 `index.html`로 리라이트한다.

## 핵심 결론

1. **취미/파일럿 규모(n≤수백 요청/일)에서는 Google Cloud Run이 실질 비용·리전 유연성 양쪽에서 가장 유리하다** — 상시 무료 등급(월 200만 요청)이 후하고 scale-to-zero가 기본이라 트래픽이 거의 없는 파일럿 기간엔 사실상 $0. 단 **무료 등급은 특정 US 리전에서만 적용되고 서울(asia-northeast3)·싱가포르는 유료 리전**이라(⚠️), 한국 사용자 지연을 낮추려 아시아 리전을 쓰면 무료 등급을 못 받는 트레이드오프가 생긴다.
2. **Fly.io는 2024년 무료 티어를 폐지했고 신규 계정은 2 VM-시간/7일 트라이얼만 받는다**(✅) — 이후 최소 상시구동 비용은 shared-cpu-1x·256MB 기준 월 약 $2, 여기에 정지 중에도 과금되는 볼륨 스토리지($0.15/GB/월)가 더해진다. `auto_stop_machines`로 Cloud Run과 유사한 scale-to-zero를 선택할 수 있다(기본은 상시구동).
3. **Railway·Render는 진입 장벽이 가장 낮다** — Railway는 $5 트라이얼 크레딧(카드 불필요) 후 Hobby $5/월(사용량 크레딧 포함), Render는 Free 웹서비스 티어가 있으나 15분 무요청 시 spin-down되고 재기동에 30~60초 콜드스타트가 걸린다(✅). 무중단을 원하면 Render Starter $7/월(512MB/0.5vCPU)부터.
4. **Neon은 서울 리전이 없다** — 가장 가까운 리전은 싱가포르(AWS `ap-southeast-1`)이며(✅), Fly.io(`sin`)·Railway(`asia-southeast1`)·Render(싱가포르)는 이 리전과 물리적으로 매칭할 수 있지만 **Cloud Run은 서울(`asia-northeast3`)에 배포 가능해도 무료 등급을 포기해야 하고, 어느 쪽이든 API 서버↔Neon DB 왕복 지연이 최소 리전 간(도쿄·서울↔싱가포르) 발생한다.**
5. **Vercel Python Functions로 FastAPI를 직접 태우는 선택지는 "Docker 배포"라는 backend.md의 전제와 근본적으로 안 맞는다** — Vercel 자체 빌드 시스템(`requirements.txt`/`pyproject.toml`)만 지원하고 Dockerfile 실행이 불가능하다(✅). 콜드스타트는 fluid compute(2025-04-23부터 신규 프로젝트 기본 ON)가 bytecode caching·pre-warming으로 완화하지만, 실행시간 상한이 Hobby 300초·Pro/Enterprise 800초(베타로 30분까지)로 캡되어 있어(✅) 장시간 LLM 호출 체인에는 제약이 될 수 있다.
6. **Vercel `vercel.json`의 external-origin rewrites가 Vercel 정적 사이트와 별도 호스팅 FastAPI를 CORS 없이 같은 도메인에 묶는 공식 패턴이다**(✅) — 브라우저 입장에서 동일 출처가 되므로 CORS 프리플라이트 자체가 불필요해진다. 단 2026-04-06 이후 신규 프로젝트는 upstream의 `cache-control` 헤더를 기본으로 CDN에 캐싱하므로, 동적 API 응답에는 `x-vercel-enable-rewrite-caching: 0`을 명시하거나 upstream이 `no-store`를 내려줘야 한다.
7. **Neon PgBouncer(transaction mode) + `asyncpg`는 알려진 함정이 있다** — Neon 문서는 "프로토콜 레벨 prepared statement는 지원"이라 명시하지만(✅), SQLAlchemy+asyncpg 커뮤니티에서는 `statement_cache_size=0`(및 `prepared_statement_cache_size=0`)를 명시적으로 꺼야 `__asyncpg_stmt_xx__` 오류를 피할 수 있다는 보고가 다수다(✅, GitHub issue 교차확인). backend.md가 `asyncpg`를 표준으로 못박은 만큼, 어느 배포처를 고르든 이 설정은 필수 체크리스트다.

## 플랫폼별 상세

### Fly.io
- **최소 비용 단** — 2024년 무료 티어 폐지(✅). 신규 계정은 2 VM-시간 또는 7일 중 먼저 도달하는 트라이얼만 제공. 이후 shared-cpu-1x·256MB 상시구동 기준 월 약 $1.94~2.02(리전별 변동). Machine을 정지해도 볼륨은 GB당 $0.15/월 계속 과금.
- **Sleep/콜드스타트** — 기본은 상시구동. `fly.toml`의 `auto_stop_machines`/`min_machines_running=0`으로 유휴 시 자동 정지·요청 시 자동 기동을 선택할 수 있음(선택형 콜드스타트).
- **Docker** — 네이티브. `Dockerfile` + `fly.toml`, OCI 이미지 기반 배포.
- **Neon 궁합** — 표준 TCP 연결. 도쿄(`nrt`)·싱가포르(`sin`) 리전 지원(✅, Fly Managed Postgres 리전 기준이나 앱 리전과 동일 목록 사용) → Neon `ap-southeast-1`(싱가포르)과 리전 매칭 가능.
- **운영 부담** — VM 단위 제어라 자유도는 높지만 `fly.toml`/`Dockerfile`을 직접 관리해야 하고, 트라이얼 종료 후 카드 등록·과금을 스스로 모니터링해야 한다.

### Railway
- **최소 비용 단** — 트라이얼 $5 크레딧(1회성, 카드 불필요, 30일 소멸)(✅). 이후 Hobby $5/월(사용량 크레딧 $5 포함, 초과분만 과금)(✅). 소규모 FastAPI+파일럿 트래픽이면 크레딧 내에서 수렴할 가능성이 높다.
- **Sleep/콜드스타트** — 서비스 단위 sleep 기능 존재(주로 dev/staging 환경에 권장)(✅). 프로덕션은 통상 상시구동으로 운용하며 이 경우 콜드스타트 없음.
- **Docker** — 지원(`Dockerfile` 또는 Nixpacks 자동 빌드).
- **Neon 궁합** — 표준 TCP. Southeast Asia Metal(싱가포르, `asia-southeast1-eqsg3a`) 리전 보유(✅) → Neon 싱가포르와 매칭 가능. Railway 자체 Postgres 애드온도 있지만 외부 Neon 연결에 제약 없음.
- **운영 부담** — 대시보드 중심의 가장 낮은 러닝커브. GitHub 연동 자동 배포.

### Render
- **최소 비용 단** — Free 웹서비스 티어 존재(750 instance-시간/월)이나 15분 무요청 시 spin-down, 재기동 콜드스타트 약 30~60초(✅). 무중단을 원하면 Starter $7/월(512MB RAM·0.5vCPU)부터, 실질 프로덕션급은 Standard $25/월.
- **Sleep/콜드스타트** — Free만 spin-down. Starter 이상은 spin-down 없음.
- **Docker** — 네이티브 지원.
- **Neon 궁합** — 표준 TCP. Render 자체 Postgres 무료 티어는 1GB 제한+30일 만료(Render Postgres 얘기, 외부 Neon 사용 시 무관). 싱가포르 리전 보유(2022년 APAC 확장)(✅) → Neon 싱가포르와 매칭 가능.
- **운영 부담** — 가장 단순한 PaaS UX. Free 티어를 쓰면 콜드스타트를 감수해야 한다.

### Google Cloud Run
- **최소 비용 단** — 상시 무료 등급 — 월 200만 요청 + vCPU-초 180,000 + 메모리 360,000 GiB-초(+아웃바운드 소량)(⚠️, 공식 페이지는 콘텐츠 길이로 전문 확인 실패했으나 3개 독립 2차 소스가 동일 수치로 교차확인). 파일럿 규모(n≤수백/일)면 사실상 $0.
- **무료 등급 리전 제약** — 무료 등급은 `us-central1`·`us-east1`·`us-west1` 3개 US 리전에서만 적용되고, 서울(`asia-northeast3`)·싱가포르(`asia-southeast1`)를 포함한 그 외 리전은 배포는 가능하나 전액 과금된다(⚠️, 2개 독립 2차 소스 교차확인 — 1차 페이지로 재확인 권장).
- **Sleep/콜드스타트** — 기본 `min-instances=0`(request-based billing)이라 완전 scale-to-zero, 콜드스타트는 수백ms~2초. `min-instances=1`로 상시 웜 인스턴스를 두면 콜드스타트가 사라지지만 월 $10~12 추가(⚠️, 2차 소스).
- **Docker** — 네이티브. 모든 OCI 컨테이너 이미지, Artifact Registry/Cloud Build 연계.
- **Neon 궁합** — 서울(`asia-northeast3`) 배포는 가능하나 Neon에는 서울 리전이 없어 최인접인 싱가포르(`ap-southeast-1`)까지 리전 간 왕복이 생긴다. 무료 등급 리전(US)에 맞추면 한국 사용자 기준 API 자체 지연이 커지는 트레이드오프.
- **운영 부담** — GCP 콘솔/IAM 학습곡선이 있지만 완전 관리형·오토스케일. 4개 옵션 중 최소 비용 단이 가장 낮다.

### Vercel Python Functions (FastAPI 직접 실행)
- **콜드스타트** — 서버리스 특성상 존재. Fluid compute가 2025-04-23부터 신규 프로젝트에 기본 활성화되어(✅) bytecode caching(Node 중심 언급)·프로덕션 pre-warming으로 완화하나, Python 런타임에 특화된 완화 효과는 문서상 명시가 적다.
- **실행시간 상한** — Hobby: 기본/최대 300초(5분) 동일. Pro/Enterprise: 기본 300초, 최대 800초(GA), 확장 베타로 최대 1800초(30분, Node/Python 특정 런타임만, `maxDuration`을 함수별로 직접 설정해야 함)(✅, Vercel 공식 문서).
- **Fluid compute 동시성** — 여러 invocation이 하나의 함수 인스턴스를 공유해 콜드스타트 빈도 자체를 낮추는 방식(✅). Node.js·Python 런타임 모두 지원.
- **번들 크기** — 표준 250MB(비압축), Fluid compute 활성 시 최대 5GB(퍼블릭 베타)(✅).
- **Docker 지원 여부** — **불가.** Vercel 자체 빌드 시스템이 `requirements.txt`/`pyproject.toml`/`Pipfile`을 감지해 빌드하며 커스텀 Dockerfile 실행 경로가 없다(✅). backend.md §10 Docker 전제(컨테이너 내부 포트 8000 고정 등)와 정면으로 어긋난다.
- **Neon 궁합** — 서버리스 함수라 invocation마다 짧은 커넥션이 열릴 수 있어 Neon PgBouncer 풀링(`-pooler` 호스트) 사용이 사실상 필수. Vercel Marketplace에 Neon 통합이 있어 환경변수 자동 주입 등은 지원되나, 이는 Node/Next.js 생태계 중심으로 문서화되어 있고 Python 쪽 1차 소스는 이번 조사에서 별도 확인하지 못함(⚠️ 미검증).
- **운영 부담** — 기존 Vercel 프로젝트에 `api/` 함수 추가하듯 배치할 수 있어 별도 배포 파이프라인이 필요 없다는 게 최대 장점이나, backend.md의 Docker·`AsyncSession` 장기 보유(§10 lazy loading·N+1 방지 loader option 등) 규칙 다수가 컨테이너 상주 프로세스를 전제로 하므로 그대로 옮기면 규칙 자체를 다시 써야 한다.

## Vercel과의 도메인/CORS 공존 패턴

현재 `vercel.json`은 다음과 같다.

```json
{
  "rewrites": [{ "source": "/((?!api/).*)", "destination": "/index.html" }]
}
```

FastAPI를 별도 상주 서버(Fly.io/Railway/Render/Cloud Run 등)에 배포하면서 기존 Vercel 프로젝트(정적 Flutter 빌드 + `api/` Node 함수 3개)와 공존시키는 방법은 크게 두 가지다.

1. **동일 도메인 리버스 프록시(권장 패턴, ✅ Vercel 공식 기능)** — `vercel.json`의 `rewrites`에 external-origin 규칙을 추가한다.
   ```json
   {
     "rewrites": [
       { "source": "/py/:path*", "destination": "https://<fastapi-host>/:path*" },
       { "source": "/((?!api/|py/).*)", "destination": "/index.html" }
     ]
   }
   ```
   브라우저는 여전히 `cookmark-woosungdevs-projects.vercel.app`만 보므로 **CORS 프리플라이트 자체가 발생하지 않는다.** 기존 catch-all 규칙(`/((?!api/).*)`)이 새 경로 프리픽스를 index.html로 삼켜버리지 않도록 negative lookahead에 새 프리픽스를 추가해야 한다(위 예시 `api/|py/`) — 이건 이 리포 `vercel.json`을 직접 읽고 확인한 구체적 함정이다. 주의점 — 2026-04-06 이후 신규 프로젝트는 upstream `cache-control` 헤더를 CDN에 기본 반영하므로, 동적 API 응답에는 `x-vercel-enable-rewrite-caching: 0` 헤더를 명시하거나 FastAPI가 `Cache-Control: no-store`를 내려줘야 의도치 않은 캐싱을 피한다.
2. **별도 서브도메인 + 명시적 CORS** — `api.<domain>`처럼 분리하고 FastAPI에서 `CORSMiddleware`로 파일럿 오리진을 화이트리스트. 도메인을 하나 더 관리해야 하고 프리플라이트 왕복이 추가되지만, 리버스 프록시 계층 없이 FastAPI 자체 타임아웃·스트리밍 정책을 그대로 쓸 수 있다는 장점이 있다.

패턴 1은 Vercel이 명시적으로 "여러 백엔드를 한 도메인으로 묶는" 용도로 문서화한 기능이라(✅) 파일럿처럼 도메인을 늘리고 싶지 않은 상황에 더 맞는다. 다만 external-origin rewrite가 Vercel Function 자체가 아니라 엣지의 리버스 프록시로 동작하는 만큼, 프록시 구간 자체의 타임아웃 상한이 얼마인지는 이번 조사에서 1차 문서로 명시적으로 확인하지 못했다(⚠️ 미검증 — 장시간 스트리밍 응답을 프록시할 계획이면 별도 확인 필요).

## Neon 궁합 공통 사항

- **풀링 필수** — Neon은 PgBouncer(transaction mode)로 최대 10,000 동시 클라이언트 연결을 지원하며(✅), `-pooler` 접미사 호스트로 접속한다. Transaction mode에서는 `SET`/`RESET`, `LISTEN`/`NOTIFY`, SQL-level `PREPARE`/`DEALLOCATE`, 임시 테이블, 세션 레벨 advisory lock을 지원하지 않는다(✅, Neon 공식 문서).
- **`asyncpg` 함정** — backend.md가 못박은 `asyncpg` 드라이버는 PgBouncer transaction mode와 조합 시 `statement_cache_size=0`(및 `prepared_statement_cache_size=0`)을 명시적으로 꺼야 `__asyncpg_stmt_xx__` 계열 오류를 피할 수 있다는 보고가 SQLAlchemy/asyncpg 이슈 트래커에 다수 있다(✅, GitHub 이슈 교차확인). Neon 접속 문자열 예 — `postgresql+asyncpg://user:password@<project>-pooler.<region>.aws.neon.tech/db?prepared_statement_cache_size=0`.
- **무료 티어 규모** — Neon Free 플랜은 프로젝트당 100 CU-시간/월(2025-10에 50→100 상향), 0.25 CU(~1GB RAM) 기준 약 400시간/월 상당, 스토리지 0.5GB, egress 5GB(✅). 5분 유휴 후 컴퓨트가 0으로 오토서스펜드된다(✅) — FastAPI 호스트도 sleep 옵션을 켜면 **DB 콜드스타트와 API 콜드스타트가 겹쳐 최초 요청이 이중으로 느려질 수 있다.**
- **리전** — Neon 지원 리전은 AWS 기준 `us-east-1`·`us-east-2`·`us-west-2`(미국), `eu-central-1`(프랑크푸르트)·`eu-west-2`(런던), `ap-southeast-1`(싱가포르)·`ap-southeast-2`(시드니), `sa-east-1`(상파울루)이며(✅), **서울·도쿄 리전은 없다.** 한국 사용자 파일럿 기준 최인접은 싱가포르.

## 냉파 규모(n≤수백 요청/일) 기준 관찰

- **트래픽 규모 자체는 어떤 옵션의 무료 등급도 넉넉히 감당한다** — Cloud Run 무료 등급(월 200만 요청)은 물론, Render Free(750시간/월)·Railway $5 크레딧·Fly.io 최소 상시구동($2/월)도 n≤수백/일 트래픽에서는 여유가 크다. 이 규모에서 결정 변수는 "비용"이 아니라 **콜드스타트 허용 여부**와 **리전(지연)**이다.
- **콜드스타트를 감수할 수 있으면(파일럿은 "질문 검증기"라 지연에 관대할 수 있음)** Render Free 또는 Cloud Run(min-instances=0)이 가장 저렴하다. 단 Cloud Run은 무료 등급을 온전히 누리려면 US 리전을 써야 하고, 그러면 한국 사용자 기준 API 자체 지연(비-DB 구간)이 커진다 — DB(Neon 싱가포르 등)와의 리전 매칭보다 API 서버 자체의 사용자-거리가 더 클 수 있다는 뜻.
- **콜드스타트를 배제하고 싶으면(사용자가 로딩을 "고장"으로 오인할 위험 회피)** Fly.io(상시구동 ~$2/월) 또는 Railway(Hobby $5/월)가 예측 가능한 최소 비용이며, 둘 다 싱가포르 리전을 제공해 Neon과 물리적으로 가깝게 묶을 수 있다.
- **backend.md의 Docker 전제를 그대로 지키려면 Vercel Python Functions는 후보에서 제외된다** — Docker 실행 경로 자체가 없어 backend.md §10~11 다수 규칙(포트 8000 고정, Docker entrypoint에서 alembic 자동 실행 등)이 성립하지 않는다. Vercel Python Functions를 쓰려면 backend.md를 이 티켓과 별도로 개정해야 하는 결정이 선행되어야 한다 — 이번 조사 범위 밖.
- **현재 배포(정적 Flutter + `api/` Node 함수 3개)와의 공존은 external-origin rewrite로 도메인 추가 없이 가능** — `vercel.json`에 새 경로 프리픽스(`/py/:path*` 등) 규칙만 추가하면 되고, 이미 존재하는 `/((?!api/).*)` catch-all의 negative lookahead에 새 프리픽스를 넣어주는 한 줄 수정이 필요하다(위 "Vercel과의 도메인/CORS 공존 패턴" 절 참조).
- **본 조사로 못 잰 것** — (1) Cloud Run 무료 등급 리전 제약의 1차 소스 전문 확인(콘텐츠 길이로 실패, 2차 소스 3건 교차확인에 그침), (2) external-origin rewrite 프록시 구간 자체의 타임아웃 상한, (3) Vercel Marketplace Neon 통합의 Python/FastAPI 쪽 실제 지원 범위. 실제 배포 결정 전 재확인 권장.

## 출처

[Fly.io 가격](https://fly.io/docs/about/pricing/) · [Fly.io 리전](https://fly.io/docs/reference/regions/) · [Railway 가격](https://railway.com/pricing) · [Railway 배포 리전](https://docs.railway.com/reference/deployment-regions) · [Render 가격](https://render.com/pricing) · [Render 신규 리전(APAC) 블로그](https://render.com/blog/new-regions) · [Google Cloud Run 가격](https://cloud.google.com/run/pricing) · [Cloud Run 리전 목록](https://docs.cloud.google.com/run/docs/locations) · [Vercel Python 런타임](https://vercel.com/docs/functions/runtimes/python) · [Vercel Fluid Compute](https://vercel.com/docs/fluid-compute) · [Vercel Functions 실행시간 설정](https://vercel.com/docs/functions/configuring-functions/duration) · [Vercel Rewrites](https://vercel.com/docs/routing/rewrites) · [Neon 커넥션 풀링](https://neon.com/docs/connect/connection-pooling) · [Neon 리전](https://neon.com/docs/introduction/regions) · [Neon Free 플랜 한도 FAQ](https://neon.com/faqs/free-plan-limits-and-quotas) · [SQLAlchemy asyncpg+PgBouncer 이슈](https://github.com/sqlalchemy/sqlalchemy/issues/6467) · [asyncpg+PgBouncer 트랩 가이드](https://goldlapel.com/grounds/connection-pooling/asyncpg-pgbouncer-prepared-statement-trap)
