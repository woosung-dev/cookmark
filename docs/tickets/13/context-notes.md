# 컨텍스트 노트 — 스펙 #13

작업 중 내린 결정과 근거를 계속 덧붙인다. 상속된 전제는 출처와 승인 여부를 함께 적는다.

---

## 2026-07-15 · 세션 시작

### 이 브랜치의 성격 — A/B 실험의 한 arm

사용자 지시: "#13은 A/B 테스트를 위해 진행하는 부분이고, 기존에 PR이 있는데 해당 부분은 무시하고 진행". 따라서
`feat/14-core-tracer`(PR #25, #14 구현체)는 **참조하지 않고** main에서 그린필드로 시작한다.
이번 arm의 변수 = `use dart`(dart MCP 툴) + `use context7`(라이브러리 문서 조회).

배경(출처 = 세션 메모리, 사용자 승인 이력 있음) — 직전 context7 A/B는 양쪽 arm이 같은 PoC 코드를 참조해
반증 조건이 오염됐고 판정이 inconclusive로 끝났다. 그래서 이번 재실험 조건이 greenfield다.

**오염 고지** — 세션 도입부에 상황 파악 목적으로 `feat/14-core-tracer`의 파일 트리 목록과
`docs/tickets/14/checklist.md`를 읽었다. `lib/` 코드 본문은 읽지 않았으나, 모듈 파일 구성과 이월 메모가
컨텍스트에 들어왔다. 실험 순도 판단은 사용자 몫으로 남긴다.

### 베이스 — main(그린필드)

main에는 앱 코드가 없다(docs만). 따라서 #14의 스캐폴드부터 전부 새로 만든다.
다른 arm이 남긴 빌드 산출물(`.dart_tool`·`build`·`.idea`·`cookmark.iml`)은 작업트리에 untracked로 있었고,
`build/`에 그 arm의 E2E 실행 로그(`flutter_driver_commands_0.log`·`integration_response_data.json`)가 들어 있었다.
전부 재생성 가능한 산출물이라 삭제 대신 세션 스크래치패드로 격리했다.

### 티켓 순서 = 번호순

의존 그래프(#14→#15→{#16,#17}→#18→{#19,#21}, #17→#20, 전부→#22)의 위상 정렬이 번호순과 일치한다.
별도 순서 설계 불필요.

### `.gitignore` — 표준 템플릿 병합

`flutter create`는 기존 파일을 덮어쓰지 않아 리포 고유 3줄(`.env*`·`.agents`·`.claude`)이 보존됐다.
다만 Flutter 표준 무시 규칙이 없어 빌드 산출물이 추적 대상이 됐다. coding-standards의
"표준 설정에서 벗어나지 않는다"에 따라 SDK 템플릿(`flutter_tools/templates/app/.gitignore.tmpl`)을
기억이 아닌 실물에서 읽어 그대로 병합했다. `.env.local`(GEMINI_API_KEY 보유)이 계속 무시되는 것을 확인.

### 플랫폼 — web만 생성

`--platforms=web`. ADR-0005의 "우선 타깃 = Web, 후순위 = Android 네이티브(파일럿 후)"에 맞춰
지금은 web 폴더만 둔다. Android는 나중에 `flutter create --platforms=android .`로 같은 코드베이스에 추가.
org는 `dev.woosung`(Android 패키지명 대비).

### DESIGN.md 충돌 — 정본 위계로 해소

스펙 #13 Further Notes의 정본 위계는 "화면·UX 상세 = G1 티켓 #8 resolution"이다. DESIGN.md는
**디자인 언어**(색·타이포·스페이싱·라운드)의 정본이지 화면 구조의 정본이 아니다. 현재 DESIGN.md에는
화면 층위 규정이 섞여 있고 6곳에서 스펙과 충돌한다(탭바 / 바텀시트 / 제휴 담기 / 음식 사진 / 매칭률 /
medium 배지). 특히 음식 사진은 스펙 Out of scope(이미지 보관 금지·레시피 본문 스크래핑 금지)상
소스 자체가 없다. #14의 앱 셸이 탭바냐 헤더 링크냐를 바로 가르므로 UI 착수 전에 정리한다
(프로젝트 CLAUDE.md: "UI를 만들거나 색을 바꿀 땐 DESIGN.md를 먼저 갱신한다").

이 충돌은 이번에 처음 발견한 게 아니다 — 출처 = 세션 메모리("DESIGN.md < ADR-0001, 화면 구조 충돌
2건 #18 전 정리"). 미검토가 아니라 이월된 기지 사항이다.

정리 결과 — 화면 층위 규정 5건 삭제/정정(탭바 · 바텀시트 · 제휴 담기 · 음식 사진 · 매칭률) +
medium 배지 정정. 재발 방지로 §0 "이 문서의 관할"을 신설해 DESIGN.md가 화면 구조를 새로 정하지
못하게 명시했다 — #14 이월 메모가 지적한 "화면 층위 규정이 남아 있는 한 재발한다"에 대한 대응.

**음식 사진 삭제 근거** — 스펙 Out of scope가 이미지 보관(사진은 인식 호출 후 저장하지 않는다)과
레시피 본문 스크래핑을 둘 다 금지한다. 즉 제안 카드에 넣을 음식 사진의 출처가 존재하지 않는다.
반면 `elevation.photo`·`rounded.photo` 토큰은 살렸다 — 업로드한 냉장고 사진이 로딩 중 화면에
표시되므로(G1 #8 "사진 위 스캔 시머") 쓸 자리가 남아 있다.

### 제안 라벨 색 — DESIGN.md 채택 (사용자 결정, 스펙 본문과 불일치)

두 정본이 정면으로 달랐다.
- 스펙 #13 User Story 9 · G1 #8 — 바로 가능=초록 / 애매하지만 가능=**호박** / 이것만 사면 가능=**파랑**
- DESIGN.md §2(7/14, ADR-0006 근거, PR #23) — 바로 가능=나물그린 / 이것만 사면 가능=**앰버** / 애매하지만 가능=**그레이**

사용자가 **DESIGN.md 쪽**을 선택했다. 근거 — 더 나중 문서이고 팔레트 정합적이다(파랑은 팔레트에
아예 없어 신규 색을 들여야 했다). 의미도 자연스럽다(사야 함=주의 앰버, 애매함=중립 그레이).

**주의** — 이 결정은 지금 구현 중인 스펙 #13 본문과 어긋난다. #18 구현·리뷰 때 "스펙 위반"으로
오판하지 말 것. 필요하면 #13/#18에 코멘트로 정정 기록을 남긴다.

---

## 2026-07-15 · #14 코어 관통

### 원가 기록을 T1 #6이 지정한 필드로 되돌린 건

처음엔 사용량을 `tokens: int` 하나로 뭉쳐 놨고, 페이크 fixture 숫자(1187 토큰 / $0.00054)도
근거 없이 지어냈다. T1 #6(#6) resolution을 읽고 바로잡았다.

- 실제 단가 — gemini-3.1-flash-lite **$0.25 / $1.50** per 1M in/out, thinking 토큰은 output 단가 과금.
  (T1 #6이 2026-07-13 공식 가격 페이지에서 확인)
- T1 #6이 못 박은 기록 필드 — `promptTokenCount`(+`promptTokensDetails` 모달리티) ·
  `candidatesTokenCount` · `thoughtsTokenCount` · 계산 원가 · 지연.
  **"thoughtsTokenCount 미기록 시 원가 78%가 누락될 수 있음"**. flash-lite는 thinking을 안 쓰지만
  모델명이 환경변수라 언젠가 thinking 모델이 들어올 수 있다 — 그때 조용히 틀리지 않게 필드를 남긴다.
- 원가 산식을 T1 #6 실측표 6행으로 검산했다(flash-lite 4행 + 3.5-flash 2행 전부 일치).
- 페이크 fixture는 실측표의 `flash-lite 기본·768px` 행 그대로 — 1157/295, $0.00073, 이미지 1,064.

교훈 — 스펙 본문만 읽고 짜면 선행 스파이크가 이미 확정한 계약을 놓친다. #6·#7은 스펙의 상류다.

### 리사이즈 — dart:ui 디코드 + image 패키지 인코딩

순수 Dart(image 패키지) 디코드는 12MP 사진에서 수 초가 걸린다 — 이 리사이즈가 없애려던 지연을
도로 만든다. `ui.instantiateImageCodecWithSize`로 플랫폼(브라우저) 디코더에 축소를 맡기고,
JPEG 재인코딩만 image 패키지가 한다. `getTargetSize` 콜백이 원본 크기를 주므로 768px 이하 확대를 막는다.

dart:ui 문서에 "웹은 CanvasKit 렌더러만 리사이즈 지원(HTML 렌더러는 불가)"이라는 경고가 있으나,
`--web-renderer` 플래그 자체가 Flutter 3.44에 없다(확인함) — HTML 렌더러는 폐기됐고 남은 렌더러는
전부 리사이즈를 지원한다. 낡은 주석이다.

### E2E가 유닛이 못 잡은 버그를 잡았다

`_RecognitionLoadingState`가 `SingleTickerProviderStateMixin`인데 티커를 2개(시머 애니메이션 +
경과 시간 감시) 만들고 있었다. 유닛·analyze 전부 통과했고 브라우저 E2E에서만 터졌다.
`TickerProviderStateMixin`으로 고쳤고, `late final`의 지연 생성이 dispose 시점에 티커를 새로
만드는 잠복 버그도 함께 제거했다(initState에서 명시 생성).

이전 시즌 교훈("라이브 e2e가 유닛이 놓친 버그를 잡는다")이 첫 티켓에서 바로 재현됐다.

### testWidgets로는 코어 루프를 검증할 수 없다

`testWidgets`는 FakeAsync 존이라 `dart:ui` 이미지 디코드 같은 실제 I/O Future가 완료되지 않는다 —
탭해도 phase가 `upload`에서 움직이지 않는다. 게다가 스캔 시머가 `repeat()`이라 로딩 중
`pumpAndSettle`은 영영 정착하지 않는다.

→ 업로드→인식→체크리스트 관통은 **E2E가 정본**이고(coding-standards와 일치), 위젯 테스트는
async를 타지 않는 것만 본다. E2E도 프레임이 아니라 컨트롤러 상태를 기다린다(`waitForPhase`).

### 서버리스 프록시 — Vercel 전제

스펙은 "호스팅은 구현 재량"이라 했다. Vercel Node 함수(`api/recognize.mjs`)로 잡았다 —
출처 = 세션 메모리의 "vercel login부터가 다음"(다른 arm의 이월 사항). 사용자 승인은 받지 않았다.
SDK 없이 REST + `fetch`만 쓴다(의존성 0, 빌드 단계 0).

`lowQuality`는 P1 확정 스키마에 없는 추가 필드다 — 실패 4종 중 "저품질"을 "0개 인식"과 가르려면
모델이 알려주는 수밖에 없다(#21 AC).

### 이월 — 배포

`vercel login`은 사용자만 할 수 있어 #14의 AC 2건(배포된 URL 관통 · 실 Gemini 호출)이 열려 있다.
D0 게이트(7/20)의 병목. 앱 코드·프록시 함수·빌드는 준비됐다.
