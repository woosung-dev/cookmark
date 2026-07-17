# Context Notes — #98 api-2 배포 파이프라인

자율결정 감사 추적. 결정/근거 1줄씩 append. 티켓 [#98](https://github.com/woosung-dev/cookmark/issues/98) · 결정 정본 ADR-0009 + 그릴링 #88·#76.

## 스코프 경계 (착수 전 확정)

- **#98 = 원격 절반만.** OpenAPI 스냅샷·드리프트 가드는 #99, 모델·세션·OIDC는 #100 이후 — 이 PR에 넣지 않는다.
- **파일럿 무접촉(~8/5)** — `apps/mobile`·`vercel.json`·루트 `api/`(.mjs) 무수정. 구조적으로도 안전하다: `.vercelignore`가 `/apps/api/`를 통째 제외하므로 여기 무엇을 넣어도 Vercel prod 배포 표면에 도달하지 않는다(실측).
- **세션 범위 = 절차 문서 먼저**(사용자 확정). GCP 콘솔·과금·WIF·시크릿 등록은 파운더 집행. 라이브 AC 2개(main push → health 200 · README 재현 검수)는 이 PR에서 닫히지 않는다.

## 착수 전 사실 확인 (실측)

- **cookmark GCP 프로젝트가 없다** — `gcloud projects list`에 `jetaime-dev`·`quantbridge`·Gemini 기본 프로젝트뿐. 리포에 GH secrets·variables도 0개(`gh secret list`·`gh variable list` 공백). 즉 라이브 AC는 프로비저닝 없이는 물리적으로 닫을 수 없다 — 티켓이 파운더 협업이라 적은 이유.
- **ADR-0008 36행 정정은 이미 끝났다**(#92 · ADR-0009 발행 시). 그런데 **`infra/README.md`는 아직 "자동 배포 금지 규약의 정신(#57 선례)"이라 적혀 있다** — #92의 문서 정정 범위가 `contracts/README`까지였다. 이 티켓이 `infra/README`를 재작성하므로 여기서 함께 없앤다(오독된 원칙을 남겨두면 미래 인프라 작업이 거기 묶인다 — #88의 경고 그대로).

## 결정 로그

- **deploy는 `api.yml`의 job으로 추가**(별도 `deploy-api.yml` 아님) — `needs: gate`로 **게이트 통과 코드만 배포**된다는 불변식이 한 파일에서 성립한다. 별도 워크플로면 `workflow_run` 체이닝이 필요한데 그건 기본 브랜치 버전으로 도는 함정이 붙는다. #88의 *"CI가 이미 GitHub Actions라 한 곳에 모인다"*와도 정합. 대가 — main의 무관한 푸시(docs 등)도 리비전을 하나 만든다. scale-to-zero + 사용자 0이라 비용은 0에 수렴하고, "배포된 것 = main"이 오히려 참이 된다.
- **deploy job은 프로비저닝 전까지 skip**(`if: vars.GCP_PROJECT_ID != ''`) — 가드가 없으면 시크릿 없는 main push마다 CI가 영구히 빨개진다. 파운더가 리포 변수를 넣는 순간 파이프라인이 발화한다. 실패가 아니라 skip이라 런이 green을 유지한다.
- **deploy job 전용 concurrency(`cancel-in-progress: false`)** — 상위 `api-${{ github.ref }}` 그룹은 `cancel-in-progress: true`라 연속 push 시 배포가 중도 취소된다. 배포는 직렬 대기가 맞다(취소는 러너 분을 아끼자는 것이지 배포를 죽이자는 게 아니다). 부수 효과로 리비전 롤아웃이 겹치지 않는다.
- **배포는 `deploy-cloudrun` 액션이 아니라 맨 `gcloud run deploy`** — 필요한 설정(`--port`·`--allow-unauthenticated`·`--min`)이 액션에 입력으로 없어 어차피 전부 `flags:`로 흘러야 한다. 액션이 사주는 게 사실상 없는데 ① 구글 비공식(README가 *"not an officially supported Google product"*라 명시)이고 ② 2025-09 이후 기능 커밋이 없으며 ③ 기본값이 `--update-secrets`(merge)라 워크플로에서 시크릿을 지워도 서비스에 영구히 남는 함정이 있다. 맨 gcloud는 infra README의 프로비저닝 절차와 **같은 어휘**라 문서와 파이프라인이 어긋나지 않는다 — "동률이면 지루하고 검증된 쪽".
- **포트는 컨테이너에 8000 하드코딩**(`${PORT:-8000}` 아님) — `--port=8000`이 $PORT도 8000으로 주입하므로 둘이 구조적으로 일치한다. 반대로 `${PORT:-8000}`은 `--port`를 빠뜨린 순간 Cloud Run 기본값 8080을 조용히 듣게 돼 "내부 8000 고정"(§10·티켓) 규약이 깨진 채 잘 도는 것처럼 보인다. 하드코딩은 시끄럽게 깨지고, 그게 이 경우엔 장점이다.

## 실측 확인 (조사가 아니라 이 워크트리에서 직접 돌린 것)

- **Dockerfile 관통 검증** — `docker build -f apps/api/Dockerfile apps/api` → 실 Postgres 상대로 ① 이미지 안에서 `alembic upgrade head`가 적용되고 실 DB에 `alembic_version=6b8076167b5b` 행이 남음 ② health 200 ③ `uid=999(nonroot)` ④ **PID 1이 uvicorn**(exec 형식이라 SIGTERM 직수신) ⑤ 225MB.
- **`/app` 통째 복사가 필수다** — `uv sync`는 프로젝트를 **editable로** 깐다(venv엔 `.pth`만 있고 소스가 없다). 게다가 `alembic/`·`alembic.ini`는 `src/` 밖이라 `packages=["src"]` wheel에도 안 들어간다. `.venv`만 복사하는 흔한 패턴을 쓰면 `alembic upgrade head`가 `No 'script_location' key found`로 죽는다.
- **빌드 컨텍스트는 `apps/api`여야 한다** — 리포 루트를 컨텍스트로 주면 `--mount=type=bind,source=uv.lock`이 컨텍스트 기준이라 `pyproject.toml not found`로 실패한다.
- **uv 베이스 태그 함정** — 학습 데이터가 끌리는 `uv:python3.13-bookworm-slim`은 uv 0.9.30(2026-02)에 **얼어붙어 있다**(404가 아니라 조용히 옛 버전). 현행은 trixie라 `0.11.29-python3.13-trixie-slim`으로 완전 고정했다.

## 파운더 제약 — 플랫폼 이식성 (2026-07-17 세션 중 신규 표면화)

**"플랫폼에 영향받지 않는 방식을 원한다 — BE를 AWS로 옮길 수도 있다"**(파운더 직접 진술). ADR-0009도 스펙 #96도 티켓 #98도 이 요구를 적지 않았다 — **상류 문서에 없던 제약이다.** 여기 남기지 않으면 다음 세션이 또 모르고 Cloud Run 영구 거주를 전제한다.

**주의 — 플랫폼을 바꾸자는 게 아니다.** Cloud Run은 ADR-0009가 정한 것이고 유효하다. 요구는 *불필요한 결합을 만들지 말라*는 것이다. 그래서 설계 원칙으로 번역하면 이렇다 — **결합은 가장자리에 두고 코어는 중립으로 유지한다.**

- **이동 시 상수** — Docker 이미지 · GitHub Actions(CI를 옮기는 게 아니다) · Neon(자체가 AWS 위에서 돌고 공용 인터넷으로 닿으므로 컴퓨트 이동이 DB 이동을 강제하지 않는다).
- **이동 시 변수** — gcloud 명령 · WIF · Secret Manager · Cloud Run 리소스.
- **어느 옵션이든 배포 명령은 바뀐다**(`gcloud run deploy` → `aws ecs update-service`). 그러니 그 비용을 특정 옵션에 청구하면 안 된다 — **마이그레이션 기제에 고유한 델타만** 청구한다.

이 렌즈가 §8 괄호의 해석을 뒤집을 수 있다 — **"(Docker entrypoint)"가 기제 사고가 아니라 "플랫폼 중립"을 인코딩한 것일 수 있다.** 회사 표준은 프로젝트·플랫폼을 횡단하니까. 내가 "괄호가 틀렸다"고 단정한 게 성급했을 가능성이 여기 있다. 단 **A의 롤백 킬은 플랫폼 독립적이라 AWS로 그대로 따라간다** — 이식성은 A의 장점 가중치를 올릴 뿐 A의 결함을 치료하지 않는다.

## 마이그레이션 배치 결정 — D (파운더 확정, 2026-07-18)

**옵션 D — GitHub Actions 러너에서 방금 빌드한 이미지를 `docker run IMAGE alembic upgrade head`로 배포 전 1회 실행.** 5개 옵션(A entrypoint · B Cloud Run Job · C GHA native · D GHA docker run · F 이연)을 두 번 채점했고, 이식성 제약을 넣은 재채점에서 **B·D 동점 → 파운더가 D + 리포 하드닝 선택**.

- **왜 D인가** — 이식성(파운더가 명시한 요구)에서 B를 앞선다. Job의 두 장점(러너 1개=레이스 불가 · 이미지 패리티)을 GCP 전용 리소스 없이 얻는다. Dockerfile이 CMD라 `docker run IMAGE alembic upgrade head`가 오늘 수정 0으로 돌고, `docker run --rm`이 종료 코드를 전파해 마이그레이션 실패가 배포를 막는다(실측). AWS 이동 시 시크릿 조회 스텝 ~5줄만 교체(이미지·GitHub Actions·Docker는 상수).
- **D의 유일한 대가 = 배포자 SA가 `DATABASE_URL`을 읽는다.** 마이그레이션이 러너에서 도므로 자격증명이 러너 env에 실체화된다. 이 리포가 public이라 하드닝이 **선결 조건**(infra/README §0.5). B는 비밀이 Secret Manager→Job 직행이라 이 비용이 없다 — 그게 B·D를 가른 유일한 차원이었고, 하드닝하면 D가 단독 승리(182 vs 176)한다.
- **A·E 배제 — 선호가 아니라 측정된 근거.** A는 롤백 킬(아래), E는 가드가 `alembic check`를 rc=0 false-green으로 만들어 §2 검증 앵커 무력화.
- **F 배제** — no-op 베이스라인이 유일한 공짜 리허설이다. 파이프라인 첫 항해를 실 테이블·실 유저의 #100에 얹지 않는다.
- **B에 대한 정직한 정정** — 처음 내가 "B의 GCP 락인이 rewrite"라 겁줬는데 실측 조사 결과 ECS 등가물이 `amazon-ecs-deploy-task-definition@v2`의 `run-task`+`wait-for-task-stopped` YAML 5줄이라 moderate(반나절)다. 단 B로 갔다면 GCP측 exit-code 전파를 랜딩 전 실측해야 했다(D는 이미 실측).
- **트립와이어 — VPC cliff.** AWS 이사가 DB를 private VPC(RDS·Neon PrivateLink)로 넣으면 GitHub-hosted 러너는 경로가 없어 **C/D가 죽고 B/A가 산다.** 지금은 Neon public endpoint라 미발화. 발화 조건 = "DB가 GitHub-hosted 러너에서 도달 불가해지는 첫 순간".
- **§8 개정 필요(파운더 몫)** — 규범절 "프로덕션 배포 전 자동 실행"은 D가 지킨다. 괄호 "(Docker entrypoint)"만 어긋난다. 그 괄호가 규범인지 예시인지는 회사 표준 개정이라 ADR-0009상 파운더 결정. 선례 = §9가 ADR-0009+#77 인용한 개정 이력 블록으로 교체됐다. **새 wayfinder 지도 불필요**(스펙 #96 실행 중 발견된 상류 결함).

## 롤백 킬 — 이것이 A를 죽인 결정타 (실측)

`alembic_version`이 새 리비전인 DB에 옛 이미지로 롤백하면, 옛 이미지의 `alembic/versions/`가 그 리비전을 몰라 `alembic upgrade head`가 **exit 255**, `set -e` entrypoint면 uvicorn이 영원히 안 뜬다(실측: "REACHED-UVICORN" 0회). **entrypoint 패턴은 롤백을 구조적으로 불가능하게 만든다** — 마이그레이션이 한 번 나가면 리비전을 되돌릴 수 없다. 이건 alembic+불변 이미지+리비전 롤백의 성질이라 **ECS·Fly·K8s로 그대로 이식된다**(A의 이식성 장점이 곧 지뢰의 이식성이다). D는 uvicorn이 alembic을 안 부르므로 옛 이미지가 정상 부팅 → 롤백 생존.

## 동시 마이그레이션 레이스 — 인용이 아니라 실측했다

Alembic 메인테이너가 "오토스케일 서비스의 startup 마이그레이션은 totally not correct"라 했고 이게 entrypoint 안의 유일한 실질 반대 논거라, **직접 재현했다**. 실 Postgres + 실 테이블 생성 마이그레이션(DDL + 데이터 INSERT) + 컨테이너 6개 동시 기동.

| 시나리오 | 동시 기동 | 실패 | 데이터 손상 |
| --- | --- | --- | --- |
| 부트스트랩(`alembic_version` 생성 자체를 경합) | 6 | **2** | 없음 — 1행 정확 |
| 정상 상태(새 리비전 롤아웃) | 6 | **1** | 없음 — 1행 정확 |

- **레이스는 실제로 터진다** — 동시 콜드스타트의 17~33%가 `UniqueViolationError`(부트스트랩은 `pg_type_typname_nsp_index`, 즉 `CREATE TABLE alembic_version` 자체를 경합)로 죽는다. 이론이 아니다.
- **그런데 데이터는 안 깨졌다** — 두 번 다 `race_probe` 1행. 리비전 전체가 한 트랜잭션이라 진 쪽의 `INSERT`가 `CREATE TABLE`과 함께 롤백됐다. 메인테이너가 우려한 데이터 마이그레이션 이중 적용은 **이 조건에서는 재현되지 않았다**.
- **결론 — entrypoint의 실제 대가는 "손상"이 아니라 "스케일아웃 버스트 중 일부 인스턴스가 기동 실패 → Cloud Run 재시도 → 자가 치유"다.** 시끄럽지만 자가 복구된다.
- **단 이 보호는 트랜잭션 마이그레이션에만 성립한다** — `autocommit_block`(`CREATE INDEX CONCURRENTLY`·`ALTER TYPE ADD VALUE`)이 끼면 롤백 단위가 쪼개져 보호가 사라진다. 이게 트립와이어의 발화 조건이다.

이 실측이 판단을 바꾼 지점 — "데이터가 깨진다"가 아니라 "기동이 시끄럽게 실패한다"라면 위험도가 한 단계 내려간다. 그래서 이 결정은 **공포가 아니라 비용 비교**로 내려야 한다.

## 상류 확인 — 액션 버전이 전부 v3다 (기억이 아니라 릴리스 API로 확인)

`google-github-actions/auth@v3` · `setup-gcloud@v3` · `deploy-cloudrun@v3`(2025-08~09 일괄 v3 전환). v2로 쓰면 낡는다.

**Cloud Run은 Direct WIF를 지원하지 않는다** — 구글 문서 원문: *"Cloud Run doesn't support Workload Identity Federation direct resource access. To allow access, use service account impersonation."* 일반 IAM 문서는 direct를 권장하므로 그대로 따르면 docker push까지 통과한 뒤 `gcloud run deploy`에서 권한 에러로 죽는다. 따라서 auth 액션에 `service_account:`가 **필수**다. 키 파일이 없다는 AC는 그대로 만족한다(impersonation은 키가 아니다).
