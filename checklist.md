# 냉파 UI ↔ DESIGN.md 정합 — 체크리스트

브랜치 `feat/ui-design-alignment`. 각 항목 pass/fail. 계획: `~/.claude/plans/buzzing-plotting-gadget.md`.

## 베이스라인
- [x] main에서 분기 · Flutter 3.44.4 확인
- [x] `flutter analyze --fatal-infos` 무이슈 (baseline)
- [x] `flutter test` 290 그린 (baseline)

## A. 크로스커팅
- [x] A1 폰트 번들 — Pretendard + IBM Plex Mono (스크린샷 육안 확인: 한글 Pretendard·0/3 mono)
- [x] A2 아이콘 스트로크 통일 (bookmark→outline, auto_awesome→outlined)
- [x] A3 라운드 원시 리터럴 → `Radii` 토큰 (체크박스·스켈레톤)
- [x] A4 primary press scale(0.98) — `PressableScale` (upload·request·cooked)

## B. 유닛 (pass/fail = 성공 기준 대조 — 전부 Playwright 스크린샷 대조 pass)
- [x] U1 온보딩 — 카드 r16·0/3 mono·sunken 입력·skip 링크·nudge
- [x] U2 업로드 존 — brand 카메라 그래픽·primary press
- [x] U3 인식 로딩 — 스켈레톤 시머·사진 단일 그림자·스피너 없음
- [x] U3b 매칭 로딩 — 제안 카드형 스켈레톤 시머 추가·'맞춰보는 중' 보존
- [x] U4 재료 체크리스트 — 인셋 그룹 리스트·confidence 3단·뭉뚱그림 점선 칩·레시피북 칩
- [x] U5 제안 카드 — 라벨 색+아이콘·출처 뱃지 outlined·부족칩·secondary/primary 56px
- [x] U6 레시피 북 — 카드→인셋 그룹 리스트·좌 아이콘 셀·인라인 복구·빈 상태 구성
- [x] U8 세션복원·공통 헤더 — AppBar flat·단일 링크·SectionSummary 접힘·하단바 없음

## EXIT 게이트
- [x] `dart format --set-exit-if-changed` 통과
- [x] `flutter analyze --fatal-infos` 무이슈
- [x] `flutter test` 290 그린
- [x] `bash scripts/e2e.sh` (integration_test 31) 그린
- [x] 상태별 Playwright 스크린샷 DESIGN 대조 일치 (9개 상태 + after 2개)
- [x] `design-review` 1회(독립 서브에이전트) → 지적 6건 반영·3건 기각(근거 기록)
- [x] 하드 제약 4개 유지 증거

## 하드 제약 유지 증거 (1단계)
- [x] 이벤트/산식/storage 무수정 — git diff에 app_event·storage·debug_metrics·debug_footer 없음
- [x] 푸터 `수동 수정 <n>`/`이벤트 <n>` 포맷 보존
- [x] E2E 키·텍스트·semantics 보존 — 31 케이스 그린

---

# 2단계 — 목업 풀 패리티 (파운더 결정, ADR-0001 역전). 상세는 HANDOFF.md.
- [x] P1 하단 탭 바 셸 (RootShell·NavigationBar) — `0e4d1a0`, analyze·test290·E2E31 그린
- [x] P3 목업형 제안 카드 (사진·순위·매칭% placeholder·영상 보기) — `3ac355b`, green·스크린샷 확인
- [x] P2 브랜드 히어로·워드마크·신뢰 라인 (그라디언트 스크림+흰 워드마크) — `e3fbe2c`, 스크린샷 확인·AA OK
- [x] P4 제안 상세 화면 (카드 탭→축복 단일 push, pop-with-result 토스트 메인 안착) — `8786b87`, E2E 31→32
- [x] P5 레시피 북 목업 (가짜 과금 크롬·썸네일·출처 라벨, 재료·remove 보존, chevron 생략) — `92d1862`
- [x] P6 인식 화면 (진행바·부제·ETA, 가짜 개수 생략=정직) — `9a549dd`
- [x] P7 ADR-0007 기록 + DESIGN §4·§7 갱신 + 6화면 스크린샷 대조 + 최종 게이트(290·E2E32)
- 백엔드 이월: 매칭% 실점수(프록시 스키마)·음식 사진(og:image 프록시)·담기(카트)·이어보기 타임스탬프 — ADR-0007에 명시
