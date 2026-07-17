# HANDOFF — 냉파 UI 목업 풀 패리티 (다음 세션용)

> 이 문서 하나로 이어받는다. 새 세션은 이걸 먼저 읽고 `checklist.md`·`context-notes.md`·`~/.claude/plans/buzzing-plotting-gadget.md`를 보조로 본다.

## 지금 어디까지 왔나 (2026-07-17)
브랜치 **`feat/ui-design-alignment`**, HEAD **`3ac355b`**, 작업트리 clean. `main` 금지.

**1단계(완료·머지 대기) — DESIGN.md 토큰 정합 + 마감 감사**: 폰트 번들(Pretendard+IBM Plex Mono)·아이콘 outlined·라운드 토큰·press-scale·매칭 로딩 스켈레톤·레시피 북 인셋 리스트·design-review 6건 반영. 커밋 `44d42d3`~`b57cdc4`.

**2단계(진행 중) — 목업 풀 패리티**: 파운더가 `docs/design/applied-app.jpeg`처럼 보이길 원해 **풀 패리티**를 택함. ADR-0001(측정 순도·화면2·단일페이지)을 되돌리는 재작업이다. 실행 방식 = **UI 먼저, 백엔드 나중**(파운더 결정).
- ✅ **P1** 하단 탭 바 셸 (`0e4d1a0`) — `lib/ui/root_shell.dart` 신규. 메인/레시피북 2탭, 선택 탭만 렌더(상태는 컨트롤러 보존). `app.dart` home=RootShell. `main_page`의 Navigator.push 제거→`onOpenRecipeBook` 콜백. NavigationBar 테마(app_theme). 테스트 갱신(아래).
- ✅ **P3** 목업형 제안 카드 (`3ac355b`) — `lib/ui/widgets/suggestion_card.dart` 재작성 + `photo_placeholder.dart` 신규. 사진 슬롯(홍시-틴트 placeholder)+`1위·96% 일치` 배지+라벨+출처+`영상 보기`+`이거 했어요`. 스크린샷 육안 확인 완료(목업과 유사).

## 남은 일 (순서대로)
- ⬜ **P2 브랜드 히어로·로고·아이콘·온기**: 온보딩(`onboarding_card.dart`)에 홍시 히어로 헤더 + `냉파` 워드마크(목업 screen 1의 따뜻한 상단). 업로드/버튼 leading 아이콘(카메라 등). 정본 §2가 브랜드색을 "로고·히어로·큰 필·일러스트"에 허용 — 실 사진 없이 홍시 fill/일러스트로. 지금 앱이 휑한 주원인이 이 누락이다.
- ⬜ **P4 제안 상세 화면 (push)**: 목업 screen 5. 카드 탭(SuggestionCard의 `onTap` 이미 준비됨)→상세 push(대형 사진 placeholder·`영상에서 이어보기`·있는/부족 재료·`이거 했어요`). **push는 반드시 `main_page.dart`에** 둘 것 — `navigation_test`가 명령형 push ≤1 & main_page 위치를 강제. openRecipe/markCooked 배선 재사용.
- ⬜ **P5 레시피 북 목업 스타일**: 목업 screen 6. `recipe_book_page.dart`에 프리미엄 크롬(`23/30 저장됨`+프로그레스+`무료` 배지+`프리미엄으로 무제한`) + 리스트 셀에 썸네일 placeholder + chevron. **수익화는 UI 크롬만**(파일럿 가짜 과금 — 파운더가 원함). 키 recipe-tile/remove/retry·빈상태 텍스트 보존.
- ⬜ **P6 인식 화면**: 목업 screen 2. `recognition_loading.dart`에 진행바 + `재료 N개 확인 중 · 보통 5초 정도 걸려요`. `loading-message` 키 보존.
- ⬜ **P7 ADR-0007 + 최종**: `docs/adr/0007-*.md`로 ADR-0001 역전 기록(측정 순도 완화·매칭%/사진 백엔드 이월 명시). `DESIGN.md`에 탭바/사진 반영 여부 판단. 전 게이트+E2E green, 목업 대조 스크린샷, 보고.

## 백엔드 이월 (프론트만으론 못 함 — 별도 트랙)
1. **매칭 %**: 지금은 placeholder(`suggestion_card._matchPercent`가 부족 수로 근사). 진짜는 LLM 프록시가 매치 점수를 반환해야 함 → `proxy_llm_gateway`/서버리스 함수 + `Suggestion` 모델 스키마 변경. **측정 편향 주의**(파일럿).
2. **음식 사진**: 지금은 `PhotoPlaceholder`(홍시-틴트+아이콘). 진짜는 URL og:image → 웹 CORS 때문에 프록시 엔드포인트 필요. 온보딩 히어로는 정적 자산으로 대체 가능.

## 하드 제약 (여전히 불변 — 깨면 파일럿 데이터 죽음)
1. 이벤트 로깅·카탈로그 12종(`app_event.dart`)·수동수정 산식(`debug_metrics.dart`, ADR-0003)·`storage.dart`·`debug_footer.dart` **무수정**. `git diff main...HEAD --name-only`에 이 파일들이 없어야 함(현재 없음).
2. `?debug` 푸터 `수동 수정 <n>`/`이벤트 <n>` 포맷 보존.
3. E2E 키·텍스트·semantics(`isChecked`) 보존. 불가피하면 테스트를 **의도적으로 함께 갱신**해 green 유지.
4. 명령형 Navigator.push ≤1(제안 상세만), main_page.dart에. 탭 전환은 setState(트립와이어 무관).

## 테스트 갱신 규칙 (P1에서 한 것 — 패턴 유지)
- 탭바 도입으로 `NavigationBar findsNothing`→`findsOneWidget`로 반전함: `test/ui/main_page_test.dart`(구 ADR-0001 테스트), `integration_test/core_loop_test.dart`(맨 끝 no-tab-bar 테스트). `BottomNavigationBar findsNothing`은 유지(우린 M3 NavigationBar 씀).
- `test/architecture/navigation_test.dart`: `hasLength(1)`→`lessThanOrEqualTo(1)` + 위치체크 조건부. P4에서 상세 push 추가되면 count=1이 됨.
- `recipe-book-link` 키는 유지(헤더 링크가 탭 전환). E2E/widget 테스트의 recipe-book-link 탭은 그대로 동작(탭 전환→레시피북 렌더).

## 어떻게 돌리나
```bash
# 인루프 게이트 (순서 고정)
dart format lib/ test/ integration_test/ test_driver/
dart format --output=none --set-exit-if-changed lib/ test/ integration_test/ test_driver/
flutter analyze --fatal-infos
flutter test                       # 현재 290 그린
bash scripts/e2e.sh                # integration_test 31, chromedriver 필요(설치돼 있음), ~2분
```
**시각 QA (Playwright)**: dev 전용 엔트리 `lib/main_visual_qa.dart`(파일럿 빌드 미포함). 서버:
```bash
nohup flutter run -d web-server --web-port=8099 --web-hostname=127.0.0.1 -t lib/main_visual_qa.dart > /tmp/qa.log 2>&1 &
# "is being served at" 뜰 때까지 대기(첫 빌드 ~30-60s)
```
`http://127.0.0.1:8099/?state=<state>` — state: onboarding·upload·loading·checklist·matching·suggestions·error·error-matching·recipebook·recipebook-empty. Playwright MCP로 navigate→wait 3s→screenshot(device scale, 390x844 뷰포트). **스크린샷은 repo 루트에 저장되니** 검증 후 scratchpad로 옮기고 커밋 전 지울 것.
- **Playwright MCP 함정**: 이전 세션의 automation Chrome이 프로필 락을 쥐면 "Browser is already in use" → `pkill -9 -f mcp-chrome-<id>`(sandbox 밖 `dangerouslyDisableSandbox`) + `rm -rf .../Singleton*` 후 재시도.
- CanvasKit라 wheel 스크롤이 안 먹음 → 세로로 긴 뷰포트(예 390x1700)로 전체를 한 컷에.

## 정본 위계·참조
- 시각 목표 = `docs/design/applied-app.jpeg`(6화면 목업, 이제 **비정본이 아니라 파운더가 맞추라 한 타깃**). 디자인 언어 = `DESIGN.md`. 구조는 이제 ADR-0007(작성 예정)이 ADR-0001을 대체.
- 스크린샷·근거: `<scratchpad>/qa-shots/`(세션별). 이 세션 것: p1-tabbar·p3-cards·u1~u6·err 등.

## 재배포
**절대 자동 금지.** DoD 충족 후 파운더 결정. Vercel은 `lib/main.dart` 빌드(수동 프리빌드만, main 자동배포 차단됨).
