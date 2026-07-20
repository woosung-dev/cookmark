# #141 컨텍스트 노트 — 결정과 그 근거

## 브랜치를 새로 판 이유

`feat/141-native-build`가 이미 존재하고 워크트리 `.claude/worktrees/feat-141`이 점유 중이었다. 그 브랜치는 **스파이크 팁 `6f8f982` 그 자체**라 이어가면 `main_native_smoke.dart`(랜딩 금지)와 `.metadata` 치환 결함이 기본으로 들어온다. 파운더 결정으로 이 워크트리에서 `feat/141-native-pilot-build`를 main 기준으로 새로 팠다. 옛 브랜치는 폐기 대상이다.

## cherry-pick이 아니라 경로 한정 checkout

`git checkout spike/129-native-android -- apps/mobile/android`. 커밋을 통째로 집으면 위 두 결함이 딸려온다. 경로 한정이 정확히 android 트리 19개만 스테이징한다.

`apps/mobile/lib/_spike_photo.dart`는 **건드리지 않았다** — 이미 main에 있고 `main_api_spike.dart:13`이 import하는 라이브 파일이다. 스파이크 잔재로 오인해 지우면 main이 깨진다.

## `.metadata`는 치환이 아니라 추가

스파이크는 `- platform: web`을 `- platform: android`로 **바꿔치기했다**. main은 여전히 웹을 빌드하고(E2E가 web 타깃) 웹 폐기는 명시적으로 미뤄져 있으므로 이건 결함이다. 둘 다 남긴다. 파일이 "수동 편집 금지"를 자칭하지만 이건 드리프트가 아니라 스파이크 결함의 의도적 화해다.

## 서명 가드 — 왜 `gradle.startParameter.taskNames`인가

요구는 "릴리스만 시끄럽게 실패, debug·profile·`flutter test`는 무영향"이다. 검토한 넷 중 셋을 기각했다.

- **`signingConfigs { create("release") { require(exists) } }`** — 설정 단계는 요청 태스크와 무관하게 **모든 빌드**에서 평가된다. debug 빌드까지 죽는다.
- **`gradle.taskGraph.whenReady { }`** — 동작은 하지만 전체 configuration을 다 치른 뒤에야 발화하고, Gradle 9가 조이고 있는 빌드 리스너 등록 계열이며, 훗날 configuration cache 히트 시 configuration 자체가 생략돼 가드가 조용히 안 돈다.
- **`doFirst` on `assembleRelease`** — 적극적으로 틀리다. 집합 태스크라 `packageRelease`가 APK를 이미 만든 **뒤에** 돈다. R8·AOT를 다 태우고 잘못 서명된 산출물을 남긴 다음 실패한다.
- **signingConfig 미지정** — AGP가 미서명 APK를 뱉는다. AC가 금지하는 조용한 실패 그 자체다.

채택한 `startParameter.taskNames` 검사는 설정 시점 즉시 실패하고(실측 **2초**), CC 캐시 키의 일부라 미래에도 조용히 죽지 않는다.

**알려진 구멍** — 이름에 `Release`가 없는 집합 태스크(`./gradlew build`)는 못 잡는다. `gradlew`·`gradle-wrapper.jar`가 gitignore라 클론에 존재하지 않고 이 리포의 빌드 경로는 `flutter build apk` 하나뿐이라 도달 불가다. 코드 주석에 명시했다.

## ⚠️ `java.util.Properties()` 완전 수식이 `app/build.gradle.kts`에서만 깨진다

스파이크의 `settings.gradle.kts`가 `java.util.Properties()`를 완전 수식으로 쓰고 있어 그 관용구를 복사했더니 **`Unresolved reference 'util'`** 로 죽었다.

원인 — 프로젝트 빌드 스크립트에는 Java 플러그인이 붙어 있어 `java`가 **패키지가 아니라 `JavaPluginExtension` 접근자**로 해석된다. `settings.gradle.kts`에는 그 확장이 없어서 같은 표현이 통한다. **선례를 복사하면 여기서만 깨지는 종류의 함정이라** 파일 상단에 사유 주석과 함께 `import java.util.Properties`를 넣었다.

## `.vercelignore` — Gradle 형제가 플러그인마다 는다

`android/build.gradle.kts`가 Gradle 빌드 디렉터리를 `apps/mobile/build/`로 옮기고 서브프로젝트마다 형제를 하나씩 만든다(`app` + Android 플러그인 1개당 1개). debug 빌드 1회로 7개가 새로 생겼다.

**옮긴 것을 되돌릴 수 없다** — flutter_tools의 `AndroidProject.buildDirectory`는 `parent.buildDirectory`로 **하드코딩**이라(`project.dart:868`) Gradle 쪽을 옮기면 APK를 못 찾는다. 스톡 템플릿이 `../../build`로 옮기는 이유가 정확히 이것이다.

`.vercelignore`는 부정 패턴 금지 + `/apps/mobile/build/` 통째 제외 금지(outputDirectory가 그 안이다)라 **열거밖에 방법이 없다.** 현재 형제를 전부 적고 "플러그인 추가 시 한 줄 는다 — 배포 전 `ls apps/mobile/build` 대조" 경고를 달았다.

## CI는 건드리지 않았다

`android/` 랜딩으로 `apps/mobile/**` paths 필터가 매치되지만 두 job 모두 Android SDK를 쓰지 않는다 — format은 Dart 경로 한정, analyze·test는 Gradle 무관, e2e는 web 타깃이다. **변경 불필요하고 깨지지 않는다.**

APK 게이트 추가는 기각했다. 릴리스 게이트는 **구조적으로 불가능**하다 — CI에 키가 없고, 없으면 실패하는 게 이 티켓의 AC다. debug 게이트는 이 티켓이 지키려는 것(서명·`allowBackup`·라벨)을 하나도 지키지 못하면서 NDK ~1GB + R8로 PR당 10~20분을 태운다. D0−2에 나쁜 거래다. 파일럿 후 후속 이슈로 제안한다.

## 의식적 이월

- **`dataExtractionRules` 미설정** — `allowBackup=false`는 Android 12+ 기기 간 직접 전송을 막지 않는다. 2주 파일럿에 기기 이관은 없다.
- **`tools:node="remove"` 선제 미적용** — 병합 결과를 debug APK에서 실측했고 위험 권한은 0건이다. 단 **"`INTERNET` 단독"이라던 예측은 틀렸다** — AndroidX Core가 `dev.woosung.cookmark.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`(`protectionLevel=signature`, 자기 자신에게 주는 권한이라 런타임 다이얼로그 없음)을 주입한다. 무해하지만 **런북 §4가 "하나뿐"이라 적어 두면 파운더가 D0에 멈춘다** — 실측값으로 고쳤다. 위험 권한이 실제로 잡힐 때만 `tools:node="remove"`를 넣는다.
- **이벤트 로그를 앱 밖에서 읽는 경로 없음** — 네이티브엔 `?debug`가 도달 불가라 [#143](https://github.com/woosung-dev/cookmark/issues/143)이 숨은 제스처로 치환한다. 이 티켓에서 임시 계측 표면을 만들면 #143과 충돌하므로 만들지 않았다. 핫픽스 리허설의 데이터 생존 증명은 `dumpsys`의 `firstInstallTime` 불변 + 레시피 화면 확인으로 한다(레시피와 이벤트는 같은 `Storage`/SharedPreferences 파일이라 레시피 생존 = 데이터 디렉터리 생존이다).
- **Play Store 시스템 이미지라 `run-as`·`adb root` 불가** — 릴리스 APK의 `shared_prefs/*.xml`을 직접 못 읽는다. 비-Play 이미지는 `sdkmanager`(= 없는 `cmdline-tools`)를 요구한다. D0−2에 가지 않는다.

## 검증 순서가 왜 이런가

**부정 테스트를 파운더가 키를 만들기 전에 돌렸다.** 그래야 "키 없으면 릴리스가 실패한다"를 파운더의 실제 키를 건드리지 않고 무위험으로 증명한다. 나중에 다시 증명하려면 `key.properties`를 잠시 옮겨야 하는데, 그건 실수 한 번이 서명 자격을 날리는 절차다.
