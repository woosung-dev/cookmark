# Context Notes — 냉파 UI ↔ DESIGN.md 정합

자율결정 감사 추적. 결정/근거 1줄씩 append. 계획: `~/.claude/plans/buzzing-plotting-gadget.md`.

## 상위 프레이밍
- **재설계 아님, 감사·마감 패스.** `lib/theme/`가 이미 DESIGN.md 토큰을 hex 단위로 정확히 전사. 남은 격차는 적용 수준(폰트 전달·아이콘 일관성·미세 라운드·매칭 스켈레톤·레시피북 리스트화). → surgical·E2E 그린 하드 제약과 정합.

## 결정 로그
- **폰트 전달 = Mono + Pretendard 번들** (파운더 결정 2026-07-17). 근거: Flutter 3.44 웹=CanvasKit라 시스템 폰트 미해석 → 지금 숫자가 비-모노 기본 폰트로 렌더. DESIGN [타이포] "IBM Plex Mono tabular" 실충족하려면 번들 필수. Pretendard로 한글/라틴까지 Apple식 통일. (a)가역·(b)정본이 폰트명 명시·(c)측정 무영향.
- **테마 폰트 코드 불변 유지**: `sansFallback`에 이미 `'Pretendard'`, `mono`에 `'IBM Plex Mono'` 존재 → 번들만 하면 기존 fallback 체인이 해석. SF Pro는 iOS 네이티브(후순위)용으로 선두 유지.
- **베이스라인**: analyze 무이슈 · test 290 그린 확인 후 착수 (안전망).
- **시각 QA 엔트리** = `lib/main_visual_qa.dart`(신규, 파일럿 빌드 미포함). `FakeLlmGateway`+페이크 imagePicker 주입, `?state=` 쿼리로 상태 선구동 → Playwright 스크린샷. Vercel은 `lib/main.dart` 빌드라 파일럿 무영향. `?state=recipebook`은 `RecipeBookPage`를 home으로 직접(Navigator.push 없음 — 트립와이어 무영향).

## A. 크로스커팅 결정
- **A1 폰트**: `Pretendard`(가변, 6.7MB) + `IBM Plex Mono`(Regular 135KB·Medium 137KB) 번들, OFL 라이선스 동봉. 테마 코드 불변 — 기존 fallback 체인이 자동 해석. Playwright 스크린샷으로 Pretendard·mono(0/3) 렌더 육안 확인. Pretendard 실측 6.7MB는 파운더 견적 ~2–4MB보다 큼(gzip으로 완화) — 파일럿 첫 로딩 무게 인지.
- **A2 아이콘**: 은유 아이콘 outlined 통일 — 출처 뱃지 `bookmark`→`bookmark_outline`, `auto_awesome`→`auto_awesome_outlined`(suggestion_card). `add_shopping_cart`는 미션이 명시한 아이콘이라 filled 스타일이어도 유지. 나머지는 이미 outlined/stroke. 아이콘은 E2E 키가 아니라 무영향.
- **A3 라운드**: raw `6`/`7` → `Radii.chip`(체크박스·22px 블록)·`Radii.pill`(텍스트 바 스켈레톤). 한 스케일 잠금.
- **A4 press-scale**: `PressableScale`(Listener 기반, 탭 비가로챔) — 업로드·오늘뭐해먹지·이거했어요 primary에 적용. active scale .98(motion 3).
- **inline 숫자 mono 트레이드오프**: 문장 속 숫자('제외한 메뉴 N개'·'맞춰보는 중'·SectionSummary 'N개')는 `find.text`/`find.textContaining` 잠금이라 TextSpan 분리 안 함(하드제약4 우선). 독립 수치 readout(0/3·푸터)만 mono — 이미 충족. 순수 크래프트 vs E2E 보존에서 E2E 보존 채택.

## B. 유닛 결정
- **U3b 매칭 로딩**: 텍스트-only → 제안 카드형 스켈레톤 시머 추가. 시머 프리미티브를 `skeleton.dart`(`SkeletonBox`·`Shimmer`)로 추출, recognition_loading의 private `_Block`/`_Shimmer` 제거·공유(중복 제거). `matching-message` 키·'맞춰보는 중' 텍스트 보존.
- **U6 레시피 북**: 개별 카드 → iOS 인셋 그룹 리스트(surface 카드 1개 + hairline Divider). 리스트 셀 = 좌 `bookmark_outline` 아이콘(muted) + 제목 headline + 보조 footnote + 우 remove(close). 키 recipe-tile/remove/retry·'아직 저장한 레시피가 없어요.' 텍스트 보존. 빈 상태를 아이콘+텍스트로 구성(§7).

## 마감 감사 (design-review, 독립 서브에이전트 1회)
토큰 레이어는 clean 확인(색·라운드·flat·스켈레톤·AI-slop 부재). 실행한 지적:
- **F1(MEDIUM) 위계**: 제안 카드 메뉴명이 `largeTitle`(30, 화면 대제목)이라 섹션 헤더 '오늘 할 3개'와 동급 → `title`(20/600)로 강등해 헤더가 앵커 유지. 텍스트 불변이라 E2E 무영향.
- **F3(MEDIUM) press 일관성**: press-scale가 3개 primary에만 있어 나머지 filled 버튼은 무반응 → 전 화면/섹션 전폭 primary(recipe-form·failure retry·rematch·backup export)로 확장. `PressableScale`에 `enabled` 추가해 비활성 버튼은 피드백 안 줌(request-suggestions·recipe-form). 컴팩트 인라인 제출(추가·vague·import)은 다른 어포던스 클래스라 제외.
- **F5/F6/F8a(POLISH)**: 빈 제안 상태를 아이콘+문구로 구성(다른 빈 상태와 동일)·에러 카드 버튼 세로 스택(긴 폴백 라벨 2줄 접힘 제거)·매칭 스켈레톤 텍스트 라인 라운드 pill 통일.
- **기각(근거)**: F2(backup/추가 primary 강등) — 백업 CTA 강조는 파일럿 데이터 유실(카톡 인앱) 대비라 유지·추가는 입력 옆 제출 명료성. F4(디바이더 인셋 48) — 체크리스트/레시피/스켈레톤 리스트 디바이더를 앱 전체에서 16으로 일관 유지(부분 변경이 오히려 불일치). F8b(문장 속 숫자 mono) — `find.text`/`find.textContaining` 잠금이라 하드제약4 우선, §3 명명 mono 타깃(0/3·푸터)은 이미 충족.

## 2단계 P2~P7 결정 (목업 풀 패리티, ADR-0001 역전)
- **P2 히어로**: 파운더가 "그라디언트 스크림 + 흰 워드마크" 택함. 홍시→차콜 단일 그라디언트(overlay 없이)라 흰 텍스트가 하단 차콜(#241511) 위에 놓여 AA 통과 — 브랜드 필(#E8552D) 위 흰 텍스트 금지 규칙(대비 3.6) 우회. 워드마크 32px(§4 40px+ 상한 준수). 신뢰 라인은 카드가 아니라 히어로 아래 별도(흰-텍스트-온-필 회피). 히어로 200px가 800×600 테스트에서 스킵 링크를 밀어 `pumpPastOnboarding`에 ensureVisible+스크롤 리셋 함께 갱신(실기기 무영향).
- **P6 로딩**: 파운더가 "정직 버전" 택함. 진행바는 `LoadingStage`(early/mid/slow)→0.35/0.7/0.92 determinate 매핑(경과시간 실신호, indeterminate 무한 애니 회피). 가짜 "재료 N개"는 인식 중 미상이라 생략. `loading_stage.dart` 무수정(문자열 E2E 잠금).
- **P5 레시피 북**: 가짜 과금 크롬은 실 카운트×가짜 상한 30(저장 안 막음). 출처 라벨은 `url` host 파싱(youtu→유튜브 등) 렌더타임 파생 — 재료 join 앞에 붙여 `돼지고기` 등 E2E 재료 문자열 보존. remove X 유지(E2E 탭), chevron 생략(레시피 상세=2번째 push 금지).
- **P4 상세**: pop-with-result가 핵심 — "이거 했어요"는 결과와 함께 pop만, 메인이 뒤에 `_markCooked` 이어받아 토스트가 메인 위(오펀 방지). "영상 보기"는 주입 콜백(pop 없음). 단일 push는 `main_page._openDetail`에만(navigation_test 0→1). `styleOf`·`matchPercentOf`를 카드→상세 공유 top-level로 추출(드리프트 방지). 라벨 배지는 상세용 무키 위젯(카드의 `label-badge-*` 키 중복 회피). 있는 재료=레시피 재료−부족 파생(저장소 무변경, saved만), 담기=비상호작용 장식 칩. E2E +1(카드탭→상세→뒤로→재진입→이거했어요→메인 토스트·cooked 로그).
- **P7**: `docs/adr/0007` 신규(ADR-0001 역전·백엔드 이월 명시·코드가 인용하던 dangling 참조 닫음). DESIGN §4·§7 "탭 바 없음"→"하단 탭 바" 갱신. `main_visual_qa.dart`에 `detail` 상태 추가(home 직접, push 없음). 6화면 Playwright 스크린샷 전부 목업과 일치 확인(scratchpad/qa-shots).
- **하드 제약 유지 증거**: `git diff main...HEAD --name-only`에 storage·app_event·debug_metrics·debug_footer·loading_stage 없음. 매 티켓 format·analyze·test290·E2E green. 각 티켓 시맨틱 커밋.
