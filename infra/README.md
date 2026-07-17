# infra — 프로비저닝 절차

`apps/api`(FastAPI)를 **Cloud Run 서울(asia-northeast3)** 에 GitHub Actions로 자동 배포하기 위한 GCP 리소스 절차다. 결정 정본은 [ADR-0009](../docs/adr/0009-apps-api-materialization.md), 인프라 결정은 그릴링 [#88](https://github.com/woosung-dev/cookmark/issues/88), 실행은 [#98](https://github.com/woosung-dev/cookmark/issues/98).

- **무엇이 들어오는가.** 프로비저닝 절차(이 문서). 배포 워크플로는 `.github/workflows/api.yml`에 **살아야 하고**(GitHub 강제), Dockerfile은 `apps/api/`에 colocate한다 — 그래서 여기 남는 건 "GCP에 손으로 만들 것" 목록뿐이다.
- **어떤 rules가 규율하는가.** `.claude/rules/backend.md`(§8 마이그레이션 · §9.1 CORS · §10 Docker 포트) + ADR-0009.
- **IaC(Terraform) 미도입.** 도입 트리거 = **환경이 2개째(staging)** 또는 **인프라 변경자가 2명째**. 지금은 둘 다 아니고, state 백엔드를 먼저 프로비저닝해야 하는 닭-달걀이 붙는다. 재현성은 이 문서가 맡는다.

> **`apps/mobile`의 Vercel 수동 프리빌드 규약과 묶지 말 것.** [#57](https://github.com/woosung-dev/cookmark/issues/57)의 "자동 배포 금지"는 원칙이 아니라 Flutter-Web-on-Vercel 특정 버그(`buildCommand: null` + gitignored `build/web` → 빈 정적 배포) 대응이었고, **그 실패 모드는 Cloud Run에 구조적으로 없다**(파이프라인이 이미지를 빌드한다). `apps/api`는 자동 배포하고 `apps/mobile`은 수동 프리빌드를 유지한다 — 두 앱, 두 규칙이다(ADR-0009가 ADR-0008 36행을 이 근거로 정정했고, 이 README에 남아 있던 같은 오독도 #98이 함께 걷어냈다).

## 프로비저닝 인벤토리

파운더가 1회 손으로 만든다. 이후 배포는 CI가 전담한다.

| # | 리소스 | 개수 |
| --- | --- | --- |
| 0.5 | 리포 하드닝 (private 전환 또는 branch protection+SHA 핀) | 1 (선결) |
| 1 | Cloud Run 서비스 (`cookmark-api`) + `allUsers` invoker 바인딩 | 1 |
| 2 | Artifact Registry 저장소 (docker, 서울) | 1 |
| 3 | Secret Manager 시크릿 (런타임·배포자 SA 둘 다 읽음) | **1** (아래 주 참조) |
| 4 | 서비스 계정 (배포자 1 · 런타임 1) | 2 |
| 5 | Workload Identity 풀 1 + OIDC provider 1 | 2 |
| 6 | GitHub 리포 변수 | 4 |

> **시크릿이 "5개"가 아니라 1개인 이유.** 티켓 #98과 ADR-0009는 1기 비밀 5개(`GEMINI_API_KEY`·`DATABASE_URL`·카카오/구글 client secret·세션 키)를 적었는데, 그건 **1기 전체**의 목록이지 #98 시점의 목록이 아니다. 지금 `src/core/config.py`의 `Settings`가 읽는 비밀은 `DATABASE_URL` **하나뿐**이다. 나머지 4개는 값이 존재하지도 않는다 — 카카오/구글 client secret은 OIDC 앱 등록([#100](https://github.com/woosung-dev/cookmark/issues/100))이 있어야 나오고, 세션 키도 #100, `GEMINI_API_KEY`는 프록시 승계 티켓의 몫이다. **없는 값으로 시크릿을 만들 수는 없고, 만들어봐야 `--set-secrets`가 읽지도 않는 env를 주입할 뿐이다.** 각 티켓이 자기 비밀을 추가할 때 아래 §3을 한 번 더 돌리고 워크플로의 `--set-secrets`에 한 줄 더한다.

## 0.5 선결 조건 — 리포 하드닝 (배포 방식의 전제)

마이그레이션이 GitHub 러너의 `docker run`으로 돌아 `DATABASE_URL`이 러너에 실체화된다(위 §2 주). **이 리포가 지금 public이고**(branch protection·CODEOWNERS·액션 SHA 핀 전부 없음) 그대로 두면 prod DB 자격증명이 무보호 공급망 표면에 노출된다. 그래서 아래 중 **하나**를 프로비저닝 전에 한다.

- **(A) private 전환** — 가장 단순. `gh repo edit woosung-dev/cookmark --visibility private --accept-visibility-change-consequences`. 파일럿 웹(Vercel)은 별도 프로젝트라 영향받지 않는다.
- **(B) public 유지 + 하드닝** — branch protection(main) + 필수 리뷰 + 액션 SHA 핀(`allowed_actions` 제한) + `sha_pinning_required`. 오픈소스로 남기고 싶을 때.

**이 선결 조건은 §6(리포 변수 주입)과 한 묶음이다** — deploy job은 변수가 없으면 skip이라, 하드닝 없이 변수만 넣지 않는 한 무보호 러너가 실 자격증명을 만지는 창이 열리지 않는다. 순서는 **하드닝 → GCP 프로비저닝 → §6 변수**다.

## 0. 사전 준비 — 프로젝트·과금·API

```bash
export PROJECT_ID="cookmark"          # 실제 값으로 교체 (전역 고유)
export REGION="asia-northeast3"       # 서울 — 유료 리전(무료 US 등급은 ADR-0009가 의식적으로 포기)
export GITHUB_REPO="woosung-dev/cookmark"

gcloud projects create "${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"
```

**과금 계정 연결은 콘솔에서 한다** — Cloud Run 서울도 Artifact Registry도 과금 없이는 안 뜬다.
<https://console.cloud.google.com/billing/linkedaccount>

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com

export PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
echo "PROJECT_NUMBER=${PROJECT_NUMBER}"   # WIF 식별자는 프로젝트 ID가 아니라 번호를 쓴다
```

## 1. Artifact Registry — 이미지 저장소

Container Registry(`gcr.io`)는 2025-03 쓰기가 중단됐다. Artifact Registry가 유일한 경로다.

```bash
gcloud artifacts repositories create cookmark \
  --repository-format=docker \
  --location="${REGION}" \
  --description="냉파 컨테이너 이미지"
```

이미지 URI 형식은 `${REGION}-docker.pkg.dev/${PROJECT_ID}/cookmark/cookmark-api:<커밋SHA>`다.

## 2. 서비스 계정 2개 — 배포자와 런타임을 분리한다

```bash
# 런타임 — Cloud Run 서비스가 이 신원으로 돈다. 기본 Compute SA를 쓰지 않는다(구글도 권고).
gcloud iam service-accounts create cookmark-api-run \
  --display-name="cookmark-api 런타임"

# 배포자 — GitHub Actions가 임퍼서네이트한다.
gcloud iam service-accounts create github-deployer \
  --display-name="GitHub Actions 배포자"

export RUNTIME_SA="cookmark-api-run@${PROJECT_ID}.iam.gserviceaccount.com"
export DEPLOYER_SA="github-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
```

배포자 권한 — **`run.admin`이 아니라 `run.developer`다.**

```bash
# 배포(리비전 생성·갱신)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${DEPLOYER_SA}" \
  --role="roles/run.developer"

# 이미지 push
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${DEPLOYER_SA}" \
  --role="roles/artifactregistry.writer"

# 런타임 SA를 서비스에 붙이려면 그 SA에 대해 actAs가 필요하다 — 프로젝트 전역이 아니라 그 SA 리소스에만 준다.
gcloud iam service-accounts add-iam-policy-binding "${RUNTIME_SA}" \
  --member="serviceAccount:${DEPLOYER_SA}" \
  --role="roles/iam.serviceAccountUser"
```

> **왜 `run.admin`이 아닌가.** `--allow-unauthenticated`는 IAM 정책 쓰기(`run.services.setIamPolicy`)라 `run.developer`엔 없다. 그래서 **공개 바인딩은 §5에서 파운더가 1회 손으로** 하고 CI는 그 플래그를 쓰지 않는다. CI가 IAM을 못 바꾸는 상태로 남는 게 최소권한이다.

> **배포자 SA도 `DATABASE_URL`을 읽는다 — 이건 배포 방식(마이그레이션을 러너의 `docker run`으로 실행)의 대가다.** §3에서 배포자 SA에 `secretAccessor`를 붙인다. 마이그레이션이 러너에서 도므로 자격증명이 러너 env에 실체화되는데, **이 리포가 public이면 그 러너가 공급망 위험 표면**이 된다. 그래서 §0.5 하드닝이 이 방식의 **선결 조건**이다 — Cloud Run Job(배포 대안) 대신 이 방식을 고른 이유와 그 대가는 `context-notes.md`에 있다.

## 3. Secret Manager — `DATABASE_URL`

Neon 콘솔에서 **pooled** 연결 문자열을 받아 `postgresql+asyncpg://` 스킴으로 바꾼다(`asyncpg` 드라이버 + PgBouncer 경유 — `statement_cache_size=0`은 앱 코드가 강제한다).

```bash
printf '%s' 'postgresql+asyncpg://<user>:<pw>@<host>-pooler.<region>.aws.neon.tech/<db>?ssl=require' \
  | gcloud secrets create cookmark-database-url --data-file=-

# 런타임 SA(서빙 시 --set-secrets 주입) + 배포자 SA(CI가 마이그레이션 전 조회) 둘 다 읽는다.
gcloud secrets add-iam-policy-binding cookmark-database-url \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding cookmark-database-url \
  --member="serviceAccount:${DEPLOYER_SA}" \
  --role="roles/secretmanager.secretAccessor"
```

`echo`가 아니라 `printf`다 — `echo`는 개행을 붙이고 그게 연결 문자열에 그대로 들어간다.

값 회전은 `gcloud secrets versions add cookmark-database-url --data-file=-`. **시크릿 env는 인스턴스 기동 시점에 1회 해석되므로 `:latest`로 회전해도 도는 인스턴스는 안 바뀐다** — 새 리비전을 배포해야 반영된다.

**비-비밀은 Secret Manager에 넣지 않는다**(§9.1). `CORS_ALLOWED_ORIGINS`는 평문 env고 **1기 배포 값은 빈 목록**이다 — 허용 origin이 로컬 개발 origin뿐이라 배포된 API를 소비하는 웹이 없다(ADR-0009 접속 절). 그래서 워크플로가 아예 설정하지 않고 앱 기본값(빈 목록)에 맡긴다.

> ⚠️ **트립와이어 — #100 인증이 #98보다 먼저 랜딩해 배포 시크릿이 늘었다.** 이 티켓(#98)이 쓰일 땐 앱이 읽는 비밀이 `DATABASE_URL` 하나였는데, 그 사이 [#100](https://github.com/woosung-dev/cookmark/issues/100)이 머지돼 서빙 컨테이너가 부팅하려면 **`SESSION_SECRET`·`KAKAO_CLIENT_SECRET`·`GOOGLE_CLIENT_SECRET`(비밀 3)** 과 **`KAKAO_CLIENT_ID`·`GOOGLE_CLIENT_ID`(비-비밀 env 2)** 도 필요하다(`src/core/config.py`의 `Settings` 필수 필드 — 없으면 import 시점에 `ValidationError`). **첫 실 배포 전에** 세 가지를 함께 해야 한다.
>
> 1. 위 §3 절차를 비밀 3개(`cookmark-session-secret`·`cookmark-kakao-client-secret`·`cookmark-google-client-secret`)에 대해 반복하고 두 SA에 `secretAccessor` 부여. 값은 #100 README의 IdP 콘솔 등록에서 나온다.
> 2. `api.yml` deploy job의 `--set-secrets`에 세 비밀을, 마이그레이션 `docker run` env에 여섯 필드 전부를 추가한다(마이그레이션도 `get_settings()`를 거쳐 전 필드를 검증한다). client id 2개는 비-비밀이므로 `--set-env-vars` 또는 리포 변수로 넣는다.
> 3. 인벤토리(위 표)의 시크릿 수를 1 → 4로 갱신.
>
> **미룰 수 있는 이유** — deploy job은 리포 변수가 없으면 skip이라 그전엔 발화하지 않는다. 하지만 파운더가 프로비저닝을 마치고 첫 배포를 돌리는 순간 발현하므로, IdP 등록(#100)과 **한 세션에서** 처리하는 게 자연스럽다.
>
> **#103 갱신 — 시크릿 5개째가 실체화됐다.** [#103](https://github.com/woosung-dev/cookmark/issues/103) 레시피 북이 저장 시 재료 추출을 하면서 `Settings`가 **`GEMINI_API_KEY`(비밀)** 를 필수로 읽는다 — ADR-0009 "1기 비밀 5개"의 마지막 조각이다. 위 1·2단계에 `cookmark-gemini-api-key`를 함께 포함할 것(값은 루트 `.env.local`의 기존 파일럿 키 재사용). 인벤토리 최종 수는 1 → **5**. `GEMINI_MODEL`은 기본값(`gemini-3.1-flash-lite`)이 있는 비-비밀이라 시크릿도 env도 불요 — 모델 교체 시에만 `--set-env-vars`로 넣는다.

## 4. Workload Identity Federation — 키 파일 없는 인증

```bash
gcloud iam workload-identity-pools create github \
  --location="global" \
  --display-name="GitHub Actions"
```

**attribute condition은 생략 불가다.** GitHub은 전 테넌트가 **issuer URL 하나**를 공유하므로, 조건이 없으면 **지구상 아무 리포나** 이 풀이 받아주는 토큰을 만들 수 있다. gcloud도 이를 강제해 조건 없이는 provider 생성을 거부한다.

```bash
gcloud iam workload-identity-pools providers create-oidc cookmark \
  --location="global" \
  --workload-identity-pool="github" \
  --display-name="cookmark 리포" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository == '${GITHUB_REPO}'"
```

이 리포만 배포자 SA를 임퍼서네이트할 수 있게 묶는다.

```bash
gcloud iam service-accounts add-iam-policy-binding "${DEPLOYER_SA}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/${GITHUB_REPO}"
```

IAM 바인딩은 **매핑된 이름**(`attribute.*`)을 쓰고 위 CEL 조건은 **원본 클레임**(`assertion.*`)을 쓴다 — 서로 바꿔 쓸 수 없다.

> **Cloud Run은 Direct WIF를 지원하지 않는다** — 구글 문서 원문: *"Cloud Run doesn't support Workload Identity Federation direct resource access. To allow access, use service account impersonation."* 일반 IAM 문서는 direct를 권장하지만 여기선 안 된다. 그래서 위처럼 **배포자 SA를 경유**한다. 임퍼서네이션은 키가 아니므로 "키 파일 없음"은 그대로 성립한다.

## 5. Cloud Run 서비스 — 1회 생성 + 공개 바인딩

CI는 **기존 서비스를 갱신만** 한다. 최초 생성과 공개 바인딩은 여기서 1회 한다.

```bash
# 자리표시자 이미지로 서비스를 만든다 — 진짜 이미지는 CI가 넣는다.
gcloud run deploy cookmark-api \
  --image="us-docker.pkg.dev/cloudrun/container/hello" \
  --region="${REGION}" \
  --service-account="${RUNTIME_SA}" \
  --port=8000 \
  --min=0 \
  --max-instances=3 \
  --no-allow-unauthenticated

# 공개 — 이 바인딩은 리비전이 바뀌어도 유지된다(서비스 레벨 IAM).
gcloud run services add-iam-policy-binding cookmark-api \
  --region="${REGION}" \
  --member="allUsers" \
  --role="roles/run.invoker"
```

> 조직 정책 `constraints/iam.allowedPolicyMemberDomains`(도메인 제한 공유)가 켜져 있으면 `allUsers` 바인딩이 거부된다. 개인 프로젝트(조직 미소속)면 기본적으로 걸리지 않는다. 막히면 `gcloud org-policies describe iam.allowedPolicyMemberDomains --project=${PROJECT_ID}`로 확인한다.

## 6. GitHub 리포 변수 4개 — 이걸 넣는 순간 파이프라인이 발화한다

**전부 비밀이 아니다**(식별자일 뿐). 그래서 **GitHub Secret은 0개**이고, 비밀은 Secret Manager → Cloud Run으로 직행해 CI를 통과하지 않는다.

```bash
gh variable set GCP_PROJECT_ID   --body "${PROJECT_ID}"  --repo "${GITHUB_REPO}"
gh variable set GCP_DEPLOYER_SA  --body "${DEPLOYER_SA}" --repo "${GITHUB_REPO}"
gh variable set GCP_RUNTIME_SA   --body "${RUNTIME_SA}"  --repo "${GITHUB_REPO}"
gh variable set GCP_WIF_PROVIDER --repo "${GITHUB_REPO}" \
  --body "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/providers/cookmark"
```

`GCP_WIF_PROVIDER`는 **프로젝트 번호**를 쓴다(ID 아님). `api.yml`의 deploy job은 `vars.GCP_PROJECT_ID`가 비어 있으면 통째로 skip하므로, **이 4개를 넣기 전까지 main push는 green을 유지**하고 넣는 순간부터 배포가 돈다.

## 7. 검증 — 절차가 실제로 재현됐는지

```bash
gcloud run services describe cookmark-api --region="${REGION}" --format='value(status.url)'
gcloud secrets list --filter="name:cookmark-database-url"
gcloud iam workload-identity-pools providers describe cookmark \
  --location=global --workload-identity-pool=github --format='value(attributeCondition)'

curl "$(gcloud run services describe cookmark-api --region="${REGION}" --format='value(status.url)')/api/v1/health"
# → {"status":"ok"}
```

`main`에 푸시하면 `api.yml`의 gate 통과 후 deploy job이 빌드 → 푸시 → 배포 → 스모크까지 돈다.

## 함정

- **`--port=8000`은 생략 불가.** Cloud Run 기본은 8080이라 빠뜨리면 프로브가 8080을 두드리는데 컨테이너는 8000을 듣고 있어 *"failed to start and listen on the port defined by the PORT environment variable"* 로 죽는다 — 앱을 의심하게 만드는 메시지지만 원인은 플래그다. 이 플래그가 `$PORT=8000`도 함께 세팅해서 컨테이너 고정값과 구조적으로 일치시킨다.
- **`PORT`를 `--set-env-vars`로 주지 말 것.** Cloud Run이 직접 주입하는 예약 변수다.
- **`--set-env-vars`의 구분자는 콤마다.** `CORS_ALLOWED_ORIGINS`처럼 콤마를 품는 값을 넣어야 하는 날이 오면 대체 구분자 문법(`--set-env-vars "^@^KEY=a,b@KEY2=..."`)을 써야 한다. 1기엔 이 변수를 배포에 안 넣으므로 발화하지 않는다.
- **배포자 권한은 `run.developer`다.** CI 로그에 `run.services.setIamPolicy` 권한 오류가 뜨면 워크플로에 `--allow-unauthenticated`가 들어간 것이다 — 그 바인딩은 §5에서 이미 1회 했으니 플래그를 지운다.
- **시크릿 env는 기동 시 1회 해석된다.** 회전해도 새 리비전 전엔 안 바뀐다.
