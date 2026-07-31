<!-- 현행 Android 사용자 상태를 승인 기준본과 대조해 시각 결정 입력을 고정하는 전수 감사 기록. -->
# Android 상태 전수 시각 감사

이 문서는 [지도 #185](https://github.com/woosung-dev/cookmark/issues/185)의 구현 전 사실 기록이다. 제품 코드를 고치거나 새 시각 결정을 내리지 않고, 현행 `main`의 사용자 도달 상태와 [승인된 390×844 Android 기준본](../prototype-android-baseline/README.md) 사이의 차이를 고정한다.

## 감사 조건

- 제품 기준: `main` `2c05713ad53309893a45186f37c45e73f4a23154`
- 비교 기준: 승인 기준본 커밋 `76fcc4e5d22e292e6250eb6f6d57f69fd95b5fc8`
- 기기: Android API 36.1 에뮬레이터, 밀도 420dpi
- 크기: 390×844dp(1024×2216px), 360×800dp(945×2100px), 411×914dp(1080×2400px)
- 상태 근거: `lib/main_visual_qa.dart`, `integration_test/core_loop_test.dart`, `integration_test/api_cutover_test.dart`, 실제 Android 렌더
- 캡처는 시스템 상태·내비게이션 바까지 포함한다. 승인 기준본은 시스템 크롬을 정본에서 제외하므로, 둘은 앱 콘텐츠 영역만 비교한다.
- Android에서 `main_visual_qa.dart`의 URL query가 상태를 바꾸지 못해 감사 중 Android initial route도 읽도록 임시 계측했다. 제품 코드에는 남기지 않았다.

## 결론 요약

1. 승인 기준본의 여섯 상태는 모두 현행 앱에 대응하지만, 가장 큰 차이는 **사진 자리의 시각적 무게**, **전체 밀도**, **Material 아이콘과 하단 선택 pill**이다. 제안·상세·레시피 북은 실제 대표 이미지 대신 동일한 수저 아이콘 placeholder를 반복하고, 온보딩은 사진 대신 200dp 브랜드 그라디언트를 쓴다.
2. 커스텀 error card와 reset dialog는 색·radius·elevation을 디자인 토큰으로 통제한다. 반면 SnackBar는 테마가 없어 Android Material 3 기본 full-width 검정 막대로 렌더된다. 현재 캡처에서 가장 명확한 기본 Material 누수다.
3. 390×844, 360×800, 411×914에서 `RenderFlex overflow`는 기록되지 않았다. 다만 390×844에서도 느린 인식의 취소 버튼, 매칭 loader/error, 체크리스트 CTA가 첫 뷰포트 아래로 밀린다. 360×800에서는 같은 밀림과 함께 온보딩 보조 문구가 두 줄로 바뀐다.
4. `main_visual_qa.dart`는 직접 기준 상태 중심이다. empty success, stale/rematch, SnackBar, dialog, keyboard, 서버 hydrate/error, 저장 중/실패, import, 주간 리포트는 E2E에는 있지만 시각 QA 진입점에는 없다. 또한 recipe book을 직접 mount해 실제 하단 탭을 생략한다.

## 승인 기준본 직접 대응 상태

| 승인 기준본 | 현행 진입점 | 실제 캡처 | 감사 사실 |
| --- | --- | --- | --- |
| 온보딩 | 첫 실행, 레시피 0개 | [390×844](screenshots/390x844/01-onboarding.png) · [360×800](screenshots/360x800/01-onboarding.png) · [411×914](screenshots/411x914/01-onboarding.png) | 구조는 대응한다. 사진의 시각적 무게 대신 고정 200dp 그라디언트 hero가 지배하고, 360dp에서는 카드 보조 문구가 2줄이 된다. |
| 재료 인식 | 업로드 후 `recognizing` | [초기](screenshots/390x844/03-recognition-loading.png) · [10초 경과](screenshots/390x844/03b-recognition-slow-cancel.png) | 4:3 사진, scan shimmer, skeleton은 대응한다. 10초 뒤 나타나는 취소 버튼은 390×844 첫 뷰포트 밖이다. |
| 재료 체크리스트 | `checklist` | [390×844](screenshots/390x844/04-checklist.png) · [360×800](screenshots/360x800/02-checklist.png) | confidence 3단과 뭉뚱그림 영역은 대응한다. 행과 섹션 간격 때문에 390/360 모두 CTA가 첫 뷰포트 밖이다. |
| 제안 | `suggestions` | [390×844](screenshots/390x844/06-suggestions.png) · [360×800](screenshots/360x800/03-suggestions.png) · [411×914](screenshots/411x914/02-suggestions.png) | 카드 계층은 대응한다. 대표 이미지 대신 action tint + Material 수저 아이콘이고, 360dp 첫 뷰포트에는 1개 카드와 다음 이미지 일부만 보인다. |
| 제안 상세 | card push | [390×844](screenshots/390x844/07-detail.png) · [360×800](screenshots/360x800/04-detail.png) | 16:9 hero와 재료 구획은 대응한다. hero 역시 placeholder이며 back/play/cart가 Material icon이다. |
| 레시피 북 | 실제 하단 탭 | [390×844](screenshots/390x844/10-recipe-book.png) | quota·입력·목록·백업 순서는 대응한다. 목록 이미지도 같은 placeholder다. visual QA의 `recipebook` 상태는 이 실제 경로와 달리 `RecipeBookPage`를 직접 mount해 탭 바를 누락한다. |

업로드 준비 상태는 승인 여섯 화면에 별도 판이 없지만 코어 루프의 상시 상태다: [390×844 캡처](screenshots/390x844/02-upload.png).

## 기준본 밖 파생 상태 행렬

`캡처 없음`은 사용자 상태가 없다는 뜻이 아니라, 현행 visual QA 진입점이 없다는 뜻이다. 해당 행은 코드와 E2E로 도달 가능성을 확인했다.

| 영역·상태 | 사용자 도달 근거 | 캡처 | 현행 표현과 남은 시각 질문 |
| --- | --- | --- | --- |
| 인식 초기·중간·느림 | 업로드 뒤 latency 경과 | [초기/중간](screenshots/390x844/03-recognition-loading.png) · [느림](screenshots/390x844/03b-recognition-slow-cancel.png) | 진행률과 문구가 바뀌지만 긴 skeleton이 취소 조작을 아래로 민다. 파생 기준본이 필요하다. |
| 인식 실패 4종 | empty, low quality, error, timeout | [empty 대표](screenshots/390x844/08-recognition-error.png) | 같은 custom danger card의 문구·버튼 변형이다. 카드 자체는 토큰화됐지만 한/두 버튼 밀도 규칙은 미정이다. |
| 인식 결과 0개 | 성공했으나 체크할 항목 없음 | 캡처 없음 | `_EmptyChecklistHint`와 수동 추가 bar로 복구한다. empty baseline이 없다. |
| confidence·뭉뚱그림·수동 추가 | 체크리스트 행 탭, 인라인 치환, 하단 입력 | [기본](screenshots/390x844/04-checklist.png) · [뭉뚱그림 입력+키보드](screenshots/390x844/13-vague-input-keyboard.png) | 앱 입력과 Android 키보드가 함께 나타난다. 키보드가 올라와도 fixed add bar가 남고, 뭉뚱그림 인라인 입력은 그 위에 존재한다. |
| 매칭 loading | CTA 탭 뒤 `matching` | [3회 스크롤 뒤](screenshots/390x844/05-matching-loading.png) | checklist가 펼쳐진 채 loader가 뒤에 붙어 첫 뷰포트에는 상태 변화가 보이지 않는다. fixed add bar도 남는다. |
| 매칭 실패 | network/error/malformed response | [3회 스크롤 뒤](screenshots/390x844/09-matching-error.png) | 펼친 checklist 뒤 custom error card가 붙어 실패도 첫 뷰포트에서 보이지 않는다. |
| 제안 0개 성공 | matching 성공, 결과 없음 | 캡처 없음 | `no_meals_outlined` Material icon empty state가 있다. 파생 기준본이 없다. |
| stale·다시 제안 | 제안 뒤 체크리스트 재수정 | 캡처 없음 | stale banner와 rematch 동작은 E2E만 있다. 정보 우선순위·motion 기준이 없다. |
| “이거 했어요” 실행취소 | 제안/상세의 cooked action | [390×844](screenshots/390x844/14-cooked-snackbar.png) | full-width 검정 Material SnackBar가 탭 바 바로 위에 붙는다. 앱의 surface·radius 언어와 다르다. |
| 레시피 북 empty | 저장 레시피 0개 | [390×844](screenshots/390x844/11-recipe-book-empty.png) | empty copy와 backup section이 같은 페이지에 온다. 직접 기준본의 full 상태와 별도 파생 기준이 필요하다. |
| 레시피 삭제 실행취소 | 행 X 탭 | [390×844](screenshots/390x844/15-recipe-remove-snackbar.png) | cooked와 같은 기본 SnackBar다. 삭제 action은 작고 generic close icon이다. |
| 레시피 폼 거절·저장 중·잠김 | 빈/오류 입력, 추출 중, 서버 hydrate 중 | 캡처 없음 | inline copy, CTA progress, disabled form을 E2E가 검증한다. visual QA 상태는 없다. |
| 레시피 저장 실패·재시도 | LLM/서버 실패 | 캡처 없음 | `RecipeAddFailureCard`가 메인·레시피 북에 공용으로 붙는다. 카드 배치 기준이 없다. |
| 서버 hydrate loading/error | API cutover 부팅 | 캡처 없음 | row skeleton 또는 inline error와 retry가 있다. direct APK visual QA로 재현하는 진입점이 없다. |
| 백업 export/import | 내보내기, 오류, preview, importing | 캡처 없음 | SnackBar, dialog, disabled progress가 섞인다. 각 transient 상태 기준이 없다. |
| 주간 리포트 | 마지막 백업 뒤 7일 | 캡처 없음 | `WeeklyReportBanner`가 backup 부근에 추가된다. 긴 콘텐츠 기준과 함께 결정해야 한다. |
| 파운더 debug footer | 앱 제목 long press | [dialog 배경에 함께 보임](screenshots/390x844/16-reset-dialog.png) | 일반 사용자 트리에는 없지만 실제 APK 상태다. checklist 아래 긴 콘텐츠로 추가된다. |
| 기록 초기화 dialog | debug footer의 초기화 | [390×844](screenshots/390x844/16-reset-dialog.png) | surface, 16dp radius, elevation 0은 custom theme다. action 정렬·padding과 scrim은 AlertDialog 기본 구조를 따른다. |
| Android 시스템 UI | status bar, gesture bar, Gboard | [키보드 대표](screenshots/390x844/13-vague-input-keyboard.png) | 앱이 소유하지 않는 후보이므로 승인 기준본과 픽셀 일치를 강제할지 플랫폼 예외로 둘지 별도 결정이 필요하다. |
| 카카오 인앱 브라우저 배너 | Web user agent | 캡처 없음 | Android APK 사용자 상태가 아니다. 의도적으로 남은 Web/E2E 경로이며 Android 기준본 행렬에서는 제외한다. |

## Material 누수와 화면별 임의 값 인벤토리

| 분류 | 코드 근거 | 실제 영향 |
| --- | --- | --- |
| 부분 `ColorScheme` | `theme/app_theme.dart`의 `ColorScheme.light`는 8개 핵심 색과 `outlineVariant`만 지정 | 지정하지 않은 inverse/container 계열은 SDK 기본 역할값이다. 기본 SnackBar처럼 그 역할을 소비하는 컴포넌트가 디자인 언어 밖으로 나갈 수 있다. |
| SnackBar 기본값 | `main_page.dart`, `recipe_book_page.dart`, `widgets/backup_section.dart`; `SnackBarThemeData` 없음 | [cooked](screenshots/390x844/14-cooked-snackbar.png)와 [삭제](screenshots/390x844/15-recipe-remove-snackbar.png)가 검정 full-width bar로 확인됐다. |
| Material icon family | `Icons.*`가 navigation, upload, empty, suggestion, detail, recipe row, backup에 직접 사용 | 승인 기준본이 요구하는 단일 SVG 계보가 없고, 화면마다 SDK glyph의 시각적 무게를 물려받는다. |
| NavigationBar 기본 geometry | `root_shell.dart`의 `NavigationBar`; theme는 높이·색·icon·label만 지정 | 선택 pill의 shape·너비와 destination 배치는 Material 3 기본이다. 390/360 모두 pill이 강하게 보인다. |
| AlertDialog의 남은 기본 구조 | `main_page.dart`의 `AlertDialog`; dialog theme는 surface·radius·elevation·type만 지정 | dialog shell은 앱 언어로 들어왔지만 action layout/padding과 modal scrim은 SDK 구조다. |
| 이미지 placeholder | `PhotoPlaceholder`, `SuggestionCard`, `SuggestionDetailPage`, `RecipeBookPage` | 16:9/44dp의 자리만 결정되고 동일한 Material 수저 아이콘이 반복된다. 실제 대표 이미지 수명주기 결정 전에는 직접 기준본과 가장 큰 차이가 남는다. |
| 화면별 상수 | `BrandHero`의 200dp와 추가 gradient 색 2개, photo 4:3/16:9, 44dp recipe thumbnail, photo overlay `0xCC1D1D1F` | 일부는 승인 composition에 필요한 값이지만 토큰/공유 컴포넌트/화면 예외 중 어디가 소유할지 아직 구분되지 않았다. |

커스텀된 영역도 함께 기록한다. 버튼, 입력, app bar, divider, dialog shell, navigation의 색·높이·type은 `ThemeData` 또는 공용 토큰을 사용한다. 따라서 “Material을 전부 제거”가 아니라 위 표의 남은 기본 역할과 geometry를 어떤 경계에서 통제할지가 다음 결정이다.

## 크기별 판정

| 크기 | 판정 | 관찰 |
| --- | --- | --- |
| 390×844 | overflow 없음, first-viewport 상태 피드백 문제 있음 | slow cancel, checklist CTA, matching loader/error가 접힌 아래에 있다. 시스템 크롬 포함 캡처는 승인 기준본보다 앱 콘텐츠 높이가 작다. |
| 360×800 | overflow 없음, wrap·밀림 증가 | 온보딩 보조 문구가 2줄이고 첫 suggestion card만 온전히 보인다. checklist의 vague 입력은 add bar 바로 뒤에서 잘려 다음 스크롤을 요구한다. |
| 411×914 | overflow 없음 | 같은 typography/spacing이 유지되고 더 많은 다음 카드가 보인다. 폭이 넓어져도 이미지 placeholder와 Material navigation의 차이는 그대로다. |

API 36 Flutter logcat에서 세 크기 모두 `RenderFlex overflow`, exception, error를 찾지 못했다. 이 판정은 글자 크기 확대나 번역까지 보장하지 않는다.

## 후속 결정으로 넘길 사실

- 이미지 수명주기: 온보딩 hero와 레시피 대표 이미지 gap → 지도 child의 이미지 계약 질문.
- 직접/파생 픽셀 판정: first viewport와 scroll 후 상태를 어느 판으로 비교할지 → 시각 패리티 판정 규칙과 파생 상태 기준본.
- 플랫폼 예외: status/navigation bar, Gboard, system dialog 역할 → Android 예외 범위 질문.
- 정본 계보: 제품 상태를 누락하는 visual QA route와 recipe book 직접 mount → 시각 정본·gate 질문.
- 수정 소유권: `ThemeData`/공용 component/화면 상수 중 어디서 gap을 닫을지 → 별도 경계 결정.

이 문서는 위 질문의 입력이며, 어느 해법도 선결하지 않는다.
