# cookmark

냉파 — 냉장고 사진 1장으로 재고를 파악하고 저장한 레시피 북과 매칭해 "오늘 뭐 해먹지"를 끝내는 앱. 도메인 글로서리는 `CONTEXT.md`, 에이전트 규약은 `AGENTS.md`, 결정 기록은 `docs/adr/`.

## 토폴로지 (ADR-0008 — 폴리글랏 모노레포)

```
apps/
  mobile/     # Flutter 앱 (유일한 러너블) — 파일럿 MVP
  api/        # (계약) 진짜 백엔드 — 루트 api/ 프록시의 승계자
  admin/      # (계약) 운영·CS 어드민 웹
  web/        # (계약) 웹 제품·마케팅
packages/     # (계약) api-client-ts · api-client-dart · types · ui · config · design-tokens
contracts/    # (계약) API 계약 정본 (openapi.yaml 등)
infra/        # (계약) IaC·배포 설정
api/          # 서버리스 LLM 프록시 3개 (루트 잠정 — Vercel 파일 관례)
docs/         # ADR · 스펙 · 에이전트 규약 · 코딩 스탠다드
```

"(계약)" 디렉토리는 비어 있다 — 코드가 아니라 좌표다. 각 디렉토리의 README가 무엇이 들어오는지·어떤 rules가 규율하는지·실체화 트리거를 계약한다(정본은 ADR-0008 표).

## 빠른 시작

```bash
cd apps/mobile
flutter pub get
flutter run -d chrome     # Web 빌드가 우선 타깃
```

게이트·배포 절차는 `AGENTS.md`의 명령 절을 따른다. 배포는 수동 프리빌드만 — main 자동배포는 차단돼 있다(#57).
