# 파일럿 D0 준비 게이트 — 계측·배포 검증 + 파운더 체크리스트

파일럿(n=2 단일 블라인드, ADR-0004)이 두 제품 질문에 깨끗한 신호를 내려면 D0(**2026-07-22**) 전에 계측·배포가 무결해야 한다. 계측 갭 하나가 n=2 실험 전체를 무효로 만든다. 이 문서는 D0 −5일(2026-07-17) 검증 결과와 파운더가 D0에 밟을 절차를 한 곳에 모은다.

## 검증 결과 (2026-07-17 · 전부 그린)

### 계측 — P2 킬 기준의 원본 데이터

- **이벤트 카탈로그 12종 전부 로깅** — photoUpload · recognitionDone · checklistEdit · matchingDone · suggestionsShown · suggestionOpened · cooked · cookedUndo · rematch · recipeBookChanged · backup · errorShown. E2E 카탈로그 테스트가 export JSON에 12종 전부 있음을 강제한다(부족·초과 시 실패).
- **수동 수정 산식 입력 완비 (ADR-0003)** — checklistEdit이 5종 kind를 전부 남긴다: uncheck(해제) · recheck(재체크) · add(추가) · substitute(치환) · **vagueDismiss(오탐복귀)** + path(typing/chip). `?debug` 푸터의 "수동 수정" 카운터가 이 집합을 센다.
- **원가 원장** — recognitionDone · matchingDone에 costUsd · 토큰 · model 기록. 취소된 인식 호출의 토큰도 사라지지 않는다(#36 · #42).
- **계측 격리 (ADR-0004)** — `?debug` 푸터는 URL 쿼리에 `debug`가 있을 때만 트리에 존재한다. 배우자 화면엔 위젯 자체가 없다(숨김이 아니라 부재).

### 배포

- **프로덕션 라이브** — 정본 URL이 실제 앱을 서빙하고 `?debug` 푸터가 작동한다. 신선 세션에서 이벤트 0 · 누적 원가 $0.
- **빈 배포 404 재발 차단** — main Git 자동배포 off(#57 · #58). 배포는 수동 프리빌드만.
- **CI 게이트** — 매 PR · main push에서 format · analyze · test · E2E 자동 실행(#59). 안전망은 UI 관측으로 디커플(#60), go_router 트립와이어(#62).

> ⚠️ **정본 URL** — `cookmark-woosungdevs-projects.vercel.app`. `cookmark.vercel.app`은 남의 프로젝트다(Vercel 전역 네임스페이스).

## 파운더 D0 체크리스트

### D0 전 (~7/21 · 베이스라인 종료)

- [ ] **이벤트 로그 리셋** — 관통 테스트가 만든 이벤트를 비운다. 절차는 [#41](https://github.com/woosung-dev/cookmark/issues/41)(레시피는 export→재import로 보존, 이벤트는 `previewMerge`가 무시).
- [ ] 리셋 후 `?debug`에서 **"수동 수정 0 · 인식/매칭 `-` · 누적 원가 $0.00000"** 확인. 이벤트는 재import가 backup 1건을 남기므로 **"이벤트 1"이 정상**이다(0이 아니다).
- [ ] 두 기기 각각. 배우자에겐 "기록 정리"로만 설명한다(계측 존재 비공개).

### D0 (7/22 · 실측 시작)

- [ ] 이 날부터 실제 요리 사용 시작 — 베이스라인 제약(기술 관통만)이 풀린다.
- [ ] 원가 · 수동 수정 모니터는 **파운더 기기에서만** `?debug`로.

### 파일럿 중 (D0~~8/5) — 측정 순도 규칙 (ADR-0004)

- [ ] **앱을 바꾸지 않는다** — UI · 로직 변경은 측정을 오염시킨다. 정합 리팩터(#38)는 파일럿 후.
- [ ] 배우자는 블라인드 유지 — 계측 · 가설을 노출하지 않는다.

## 판정 지표

- **지표 1 (자발 사용)** — 주 3회 업로드 세션(photoUpload).
- **P2 킬 기준** — 사진당 수동 수정이 2주 연속 주 평균 5개를 초과하면 킬(checklistEdit 5종 합, ADR-0003). 산식은 파일럿 종료까지 불변이다.
