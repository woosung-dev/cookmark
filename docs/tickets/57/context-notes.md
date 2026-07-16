# 컨텍스트 노트 — #57 (배포 결함: Git 자동배포가 빈 프로덕션을 올린다)

## 2026-07-16 · 세션

### 발견 경위

라이브 파일럿 관통 검증 중, 정본 URL `cookmark-woosungdevs-projects.vercel.app`이 **root 404**임을 발견.
앱은 정상 빌드·부팅되는데 Vercel이 정적 앱을 서빙하지 않았다. 최소 3시간(직전 Production 배포 전부 6초·빈 산출물).

### 근본 원인

- `vercel.json` `buildCommand: null` → Vercel이 `flutter build web`을 돌리지 않는다.
- `build/web`은 gitignored → 리포에 빌드 산출물이 없다.
- 그래서 **Git 통합 자동배포**(main 푸시/머지)는 `api/*` 함수만 6초에 올리고 **정적 앱은 빈 채로** 프로덕션 별칭을 덮는다 → root 404. (`api/*` 프록시는 정상 — `/api/recognize` GET→405.)

즉 **main 머지마다 프로덕션이 빈 배포로 덮인다.** PR #56(#53 머지)이 최신 빈 배포를 유발했지만, 그 전 배포들도 전부 빈 것 — 머지가 만든 결함이 아니라 배포 구성 문제.

### 정본 배포 절차 (수동 프리빌드)

`docs/tickets/13/context-notes.md`가 정한 모델을 재확인한다 — **배포는 로컬 프리빌드로만**.

```bash
flutter build web --release           # build/web 생성
vercel build --prod                   # .vercel/output 에 static(build/web)+functions(api/*) 패키징
vercel deploy --prebuilt --prod       # 프로덕션 별칭에 배포
```

검증 — `curl` root=200 + `flutter_bootstrap` 마커, `/api/recognize` GET=405.

### 이 티켓의 수정

`vercel.json`에 `"git": { "deploymentEnabled": { "main": false } }` 추가 — main 자동배포를 꺼서 머지가
프로덕션을 빈 배포로 덮지 못하게 한다. 프리뷰(PR 브랜치) 배포는 프로덕션 별칭을 안 건드리므로 무해, 유지.

### 후속(미결)

장기적으로 Git 배포에서 flutter 빌드를 배선(빌드 이미지에 Flutter 설치)할지, 수동 프리빌드를 유지할지는
별도 결정. 문서(tickets/13)는 "vercel login 없이 검증 불가"를 이유로 수동 프리빌드를 택했다 — 현 상태 유지.

### 검증 증거 (복구 시점)

- 3개 별칭(`cookmark-woosungdevs-projects` · `cookmark-mu` · `cookmark-git-main`) 전부 root=200/앱 서빙.
- 실 Gemini 관통 — `/api/recognize` 200(imageTokens 1102·gemini-3.1-flash-lite·$0.00074) → 체크리스트(confidence 3단)
  → `/api/match` 200 → "오늘 할 3개" 제안 카드(§7 배지·아이콘 포함) → 이벤트 로그(`photoUpload`·`recognitionDone`) 기록.
