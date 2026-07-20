# Context Notes — #143 계측 트리거 네이티브 등가물

자율결정 감사 추적. 티켓 [#143](https://github.com/woosung-dev/cookmark/issues/143) · 스펙 [#140](https://github.com/woosung-dev/cookmark/issues/140) · 지도 [#129](https://github.com/woosung-dev/cookmark/issues/129) · 결정 [#136](https://github.com/woosung-dev/cookmark/issues/136).

## 전제 재확인 (코드를 읽고 확인)

`debugFooterEnabled()`는 `Uri.base.queryParameters.containsKey('debug')`였다. 네이티브에서 `Uri.base`는 쿼리가 없는 cwd `file://` URI라 **항상 false**다 — 즉 파일럿 빌드에서 푸터는 영영 뜨지 않는다. 티켓이 말하는 "플랫폼이 강제한 치환"이 코드로 확인된다.

`MainController.showsDebugFooter`는 `late final`이라 생성 시점에 1회 확정됐다. 제스처로 열려면 가변이어야 하고, 그 순간 "언제 도로 닫히는가"가 새 계약이 된다.

## 결정 로그

### 1. 세션 한정 = 컨트롤러의 메모리 필드. 영속하지 않는다

`MainController`는 앱 부팅 때 만들어져 `CookmarkApp`에 주입되고, 열림 여부는 평범한 `bool` 필드다. 영속층(`storage.dart`)을 **일부러 건드리지 않았다** — 저장하는 순간 "재시작하면 도로 숨는다"가 깨지고, 배우자 기기에 잔상이 남는다. AC의 "그 세션 한정"은 **아무것도 안 하는 것**으로 달성된다.

`late final` → `bool _showsDebugFooter = false` + getter + `toggleDebugFooter()`. 컨트롤러는 이미 `ChangeNotifier`이고 `main_page`가 `ListenableBuilder`로 듣고 있어서 `notifyListeners()` 한 줄이면 푸터가 나타난다. 새 상태 관리 장치를 들이지 않았다.

### 2. 한 번 열면 끝이 아니라 토글

AC는 여는 것만 요구한다. 그런데 코드량이 같다(`= true` vs `= !_showsDebugFooter`) — 그러면 되돌릴 수 있는 쪽이 낫다. 파일럿 중 배우자가 옆에 오면 파운더가 같은 제스처로 도로 닫는다. 닫는 방법이 재시작뿐이면 파운더가 앱을 죽여야 하고, 그건 세션 복원 경로를 부르는 부작용이 있다.

### 3. 트리거는 `GestureDetector`, 위치는 앱바 타이틀 그 자체

`Text('냉파')`만 감싼다 — 앱바 전체나 `InkWell`이 아니다.

- **`InkWell`을 쓰지 않은 이유** — 잉크 리플이 곧 "여기 뭔가 있다"는 표식이다. 배우자에게 표식이 없어야 하는 게 이 티켓의 전부다.
- **히트 영역을 타이틀 글자로 좁힌 이유** — 앱바 전체를 트리거로 만들면 스크롤·오버플로 메뉴와 우발 충돌 표면이 늘고, 배우자가 우연히 길게 누를 확률도 올라간다. 파운더는 어디를 누를지 알고 있으므로 좁은 표적이 손해가 아니다.
- `AppBar.title`은 자손에게 `titleTextStyle`을 `DefaultTextStyle`로 내리므로 `GestureDetector`로 감싸도 글꼴이 그대로다(렌더 패리티 확인).

### 4. `Key('app-title')`은 테스트용이 아니라 트리거의 주소다

E2E가 `find.byKey`로 잡는 유일한 지점이다. 주입 훅을 지웠으니 테스트도 이 키를 통해 **사용자와 같은 제스처**로만 푸터를 연다. AC가 노린 "테스트는 통과하는데 실기기에서는 안 열린다의 구조적 불가능"이 여기서 성립한다.

## 검증이 진짜인지 확인 (레드 선행)

구현 **전에** E2E를 먼저 고쳐 돌렸다. 실패한 것이 정확히 제스처에 의존하는 3건이다.

- `측정 푸터는 앱바 타이틀 롱프레스로만 열린다 (#143, ADR-0004)`
- `앱을 다시 띄우면 푸터는 도로 숨는다 — 그 세션 한정이다 (#143)`
- `D0 전 기록 초기화 리허설 — 지우고 가져와도 레시피만 돌아온다 (#41)`

나머지는 그대로 통과했다 — 즉 테스트가 공허하지 않고, 이 변경 말고 다른 걸 깨지도 않았다. 구현 후 `scripts/e2e.sh` 전량 green.

유닛은 417 → 415다. 줄어든 2건이 삭제한 `?debug` 판정 테스트와 정확히 일치한다(우발적 유실 아님).

## 리뷰 반영 (2축 code-review)

- **접근성 트리로 맹검이 샌다(Standards)** — `GestureDetector`는 기본값이 `excludeFromSemantics: false`라 타이틀에 `SemanticsAction.longPress`를 공표한다. 스크린 리더가 "길게 누르기" 액션을 읽어주면 시각적 무표식은 의미가 없다. `excludeFromSemantics: true`로 껐다. **이 티켓에서 가장 값진 지적이다** — 육안 확인으로는 영원히 안 잡힌다.
- **`debug_footer.dart` 헤더 주석이 `?debug`를 계속 말한다(Spec)** — 형제 파일 3개는 갱신했는데 이것만 놓쳤다. AC의 "푸터 내용 무변경"은 **렌더되는 수치**를 말하는 것이지 소스 주석이 아니다(`'측정 (debug)'` 표시 문자열은 그대로 뒀다). 첫 줄 한국어 헤더는 다음 세션의 항해 계약이라(전역 CLAUDE.md §6) 고쳤다.
- **토글의 닫는 쪽이 테스트되지 않았다(양 축 동시 지적)** — 주석은 "다시 누르면 도로 닫힌다"고 주장하는데 두 번 누르는 테스트가 없었다. 첫 E2E에 두 번째 롱프레스 단언을 붙였다. 주장하는 동작은 잠근다.
- **세션 한정 테스트가 동어반복에 가깝다(Spec)** — `restartApp`이 컨트롤러를 새로 만드니 "새 객체의 bool이 false"를 확인하는 셈이다. 맞다. 다만 `storage`는 살아남으므로 **영속화 회귀**에는 진짜로 걸린다 — 그게 유일한 이빨이라는 걸 테스트 주석에 명시했다. 과대주장을 지우는 쪽을 택했다.
- **재시작 관용구가 3곳 중복(Standards)** — `restartApp` 헬퍼로 뽑았다. 셋 중 하나는 기존 코드지만 같은 관용구·같은 의미라 한 개만 남겨두는 게 더 나쁘다.
- **반영하지 않은 것 — 히트 영역 확대(`HitTestBehavior.opaque`)**. 양 축이 "타이틀 글자만 눌린다"고 짚었고 Spec 축은 "의도가 아니라 우연"이라고 봤다. **의도다**(위 결정 3). 앱바 전체를 트리거로 만들면 배우자의 우발 발견 표면이 커진다 — 파운더는 어디를 누를지 알고 있으므로 좁은 표적이 손해가 아니다.

## 이 티켓 밖 — 표면화

- **푸터는 프로세스가 죽을 때까지 열려 있다 — "파운더가 자리를 뜰 때"가 아니다.** Spec 리뷰가 짚은 잔여다. #41 절차상 파운더는 **배우자 기기에서** 푸터를 여는데, 프로세스를 완전히 죽이지 않고 폰을 돌려주면 그대로 열려 있다. **`AppLifecycleState.resumed`에 자동으로 닫는 배선은 일부러 넣지 않았다** — 안드로이드에서 `resumed`는 알림 하나 내렸다 올려도 발화해서 파운더가 읽는 도중에 닫히고, `WidgetsBindingObserver`는 AC가 요구하지 않은 새 장치다. 완화는 **토글**이다(결정 2 — 같은 제스처로 즉시 닫는다). 절차로 못박는 건 [#146](https://github.com/woosung-dev/cookmark/issues/146)의 #41 재작성 몫이고, 거기에 "확인 후 다시 롱프레스로 닫는다" 한 줄이 필요하다.
- **`docs/pilot/d0-readiness.md`가 아직 `?debug`를 말한다** (5곳). D0 저녁에 파운더가 읽는 운영 문서인데 이제 존재하지 않는 트리거를 가리키고, 27행의 **"이벤트 1이 정상"** 불변식은 [#146](https://github.com/woosung-dev/cookmark/issues/146)이 뒤집기로 한 바로 그 문장이다. #146의 AC는 이슈 #41·#65·#9만 지명해서 **이 리포 파일이 지명 목록에서 빠져 있다.** 코드가 아니라 문서라 이 티켓에서 고치지 않았다 — #146에 코멘트로 남겼다.
- **`docs/adr/0007`도 `?debug`를 언급**하지만 ADR은 시점 기록이라 고치지 않는다([#145](https://github.com/woosung-dev/cookmark/issues/145)의 "서술 자체는 지우지 않는다" 관례).
- **`MainController._recognize`의 성공 경로 잔여** — [#142](https://github.com/woosung-dev/cookmark/issues/142)가 넘긴 항목이다. 게이트웨이 호출 뒤의 `appendEvent`·`_saveSession`이 같은 `try` 안이라 거기서 `LlmFailure` 아닌 게 나면 같은 고착 증상이 난다. **이번에도 고치지 않았다** — #143의 AC는 트리거 치환뿐이고, 저 수정은 실패 경로 계약을 다시 여는 별개 판단이다. 여전히 열려 있다.
- **E2E는 여전히 Web 타깃이다.** AC가 명시적으로 그걸 허용한다("트리거가 플랫폼 중립이라 E2E를 네이티브로 옮기지 않고도 의미가 유지된다") — `longPress`는 Flutter 제스처 인식기 층이라 dart2js/Android VM 차이를 타지 않는다. 실기기 롱프레스 확인은 [#65](https://github.com/woosung-dev/cookmark/issues/65) D0 스모크 몫이다.

## 확인한 함정

- **`?debug`를 지우면 되돌릴 수 없다.** 웹 빌드는 아직 살아 있지만(증명 전 삭제 금지, #145) 이 트리거만은 네이티브로 단일화했다 — AC가 "맹검을 지켜야 하는 경로가 2개면 추적 표면이 2배"라고 명시한다. 웹에서도 이제 제스처로만 열린다(E2E가 웹 타깃에서 그걸 증명한다).
- **앱바는 `ListenableBuilder` 바깥에 있다.** 토글은 앱바가 아니라 body를 다시 그려야 하는데, 푸터는 body 안 `_sections()`에 있으므로 `notifyListeners()`가 정확히 필요한 곳에 닿는다. 앱바 자신은 다시 그릴 필요가 없다.
