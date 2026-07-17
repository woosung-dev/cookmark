# #98 api-2 배포 파이프라인 — 체크리스트 (walking skeleton 원격 절반)

티켓 정본은 [#98](https://github.com/woosung-dev/cookmark/issues/98), 결정 정본은 ADR-0009 + 그릴링 [#88](https://github.com/woosung-dev/cookmark/issues/88)(인프라)·[#76](https://github.com/woosung-dev/cookmark/issues/76)(스택·배포) 해소 코멘트다. 직전 태스크 #97 체크리스트는 전량 완료(PR #105 머지 · 56dc4ea).

## 세션 범위 (사용자 확정)

**절차 문서 먼저** — 티켓이 명시한 순서(*"절차를 먼저 문서로 쓰고 검수받는다"*). 코드·워크플로·README를 쓰고 Docker 절반을 로컬 실증한다. GCP 프로비저닝(프로젝트·과금·WIF·시크릿)은 README 검수 후 파운더가 집행하며, 라이브 AC 2개는 그때 닫힌다.

## 구현

- [x] 브랜치 `feat/98-deploy-pipeline` + 작업 문서(checklist·context-notes)
- [x] `apps/api/.dockerignore` — 빌드 컨텍스트 최소화(`.venv`·캐시·비밀·테스트 제외)
- [x] `apps/api/Dockerfile` — uv 멀티스테이지 · 내부 8000 고정 · non-root — **로컬 관통 실증 완료**
- [x] `.github/workflows/api.yml` — deploy job(`needs: gate` · main push · WIF · 빌드/푸시/배포/스모크) — YAML 파싱 확인
- [x] `infra/README.md` 재작성 — 프로비저닝 절차 + IaC 트리거 + 함정. **"자동 배포 금지 규약의 정신(#57)" 오독 제거**(ADR-0008 36행은 #92가 이미 정정했으나 이 파일엔 남아 있었다)
- [ ] **마이그레이션 스텝 — 파운더 결정 대기**(A entrypoint / B Cloud Run Job / D GHA docker run / F 이연). 나머지 산출물과 무관하게 +3~12줄이다
- [ ] `apps/api/README.md` — 배포 절 갱신(#98 몫이라 적힌 자리 채우기)

## AC 검증

- [ ] **로컬 실증** — `docker build` → 실 Postgres 상대로 `docker run` → entrypoint가 alembic 적용 → health 200
- [ ] WIF 인증 — 리포·CI 어디에도 키 파일·서비스 계정 JSON 없음 (grep 증거)
- [ ] 비밀이 코드·워크플로에 평문 0 (grep 증거) · 5개 목록·생성 절차는 infra README
- [ ] 배포 시 Alembic 자동 적용 — entrypoint 경로로 로컬 증명(원격은 프로비저닝 후)
- [ ] `apps/mobile`·`vercel.json`·루트 `api/` 무접촉 — 파일럿 가드(~8/5) (diff 증거)
- [ ] 프로비저닝 전 main push가 빨개지지 않음 — deploy job이 skip (가드 검증)
- [ ] ~~main push → 자동 배포 → Cloud Run URL health 200~~ — **파운더 프로비저닝 후** (세션 범위 밖)
- [ ] ~~infra README 절차만 따라 재현 가능~~ — **파운더 검수** (세션 범위 밖)

## 마무리

- [x] 인루프 게이트 — `ruff format` · `ruff check` · `mypy src/` · `pytest`(7 passed) green — 회귀 없음(변경이 src/ 무접촉)
- [x] `/code-review` 2축 — **Standards PASS · Spec PASS**. 반영 3건 — syntax 지시자 1행 이동·스크립트 인젝션 방어(env 경유)·한국어 종결 콜론 2곳. `--max-instances 3` 근거 주석 추가
- [ ] 시맨틱 커밋 → push → PR → CI green → 티켓 코멘트(잔여 파운더 항목 명시)

## 파운더에게 넘길 잔여 (세션 범위 밖 — 티켓 코멘트에도 남긴다)

1. **리포 하드닝**(private 전환 또는 branch protection + 액션 SHA 핀) — D 방식의 선결 조건(infra/README §0.5).
2. **GCP 프로비저닝** — infra/README 절차대로. 마지막에 리포 변수 4개를 넣으면 파이프라인 발화.
3. **backend.md §8 개정** — 괄호 "(Docker entrypoint)"를 "리비전/레플리카 런타임이면 배포 전 단발 실행"으로. 규범절은 무변경. 선례 = §9 개정 이력 블록.
4. **티켓 #98 AC 문구** — "entrypoint 자동 실행" → "배포 전 docker run", "시크릿 5" → "1(1기 시점)".
5. (선택) **AWS 이동 시 DB의 VPC 진입 의도** — Neon public 유지면 D 그대로, RDS/PrivateLink면 D가 죽고 B로 재결정(트립와이어).
