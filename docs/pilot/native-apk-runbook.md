# 네이티브 파일럿 APK 런북 (#141)

파일럿은 웹이 아니라 **사이드로드 APK**로 간다(지도 [#129](https://github.com/woosung-dev/cookmark/issues/129) · 스펙 [#140](https://github.com/woosung-dev/cookmark/issues/140) · ADR-0005의 배포 타깃 역전). 이 문서는 **APK를 만들고, 두 기기에 넣고, 파일럿 도중 고쳐 넣는 기계적 절차**의 정본이다.

여기 **없는 것** — 이벤트 카탈로그·계측 기대값·기록 초기화 절차·판정 지표·D0 날짜 산수·배우자에게 하는 설명. 전부 [`d0-readiness.md`](./d0-readiness.md)와 [#146](https://github.com/woosung-dev/cookmark/issues/146)이 정본이다. 두 곳에 쓰면 갈라지고, 이 리포는 이미 한 번 갈라졌었다.

절 매핑 — 키스토어 1회 생성 = §1 · 파일럿 APK 빌드 = §3 · 배우자 기기 설치 = §5 · 핫픽스 재배포 = §6.

## 1. 키스토어 — 파운더가 1회 만들고 비밀번호를 넘기지 않는다

**이 절은 파운더 전용이다.** 에이전트는 키스토어도 비밀번호도 만들지 않고 읽지도 않는다 — 서명 비밀의 보관자는 사람 한 명이다([#141](https://github.com/woosung-dev/cookmark/issues/141) 역할 분담). 소요 ~10분이고 파일럿 전체에서 딱 한 번이다.

**왜 전용 키인가.** Android는 매 설치마다 서명 인증서를 비교해 불일치를 다른 앱으로 취급한다 — **같은 키 = 업데이트(데이터 보존), 다른 키 = 신규 설치(데이터 전멸)** 다. `~/.android/debug.keystore`는 같은 머신에서 안정적으로 보이지만 그 안정성은 우연이다(Android Studio·Flutter 재설치나 `~/.android` 초기화에서 조용히 재생성된다). 키 변경은 설치 시점까지 보이지 않다가 파일럿 데이터를 통째로 지운다.

```bash
mkdir -p "$HOME/.cookmark"
keytool -genkeypair -v \
  -keystore "$HOME/.cookmark/cookmark-pilot.jks" \
  -alias cookmark-pilot \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=cookmark pilot, OU=cookmark, O=cookmark, L=Seoul, C=KR"
```

키스토어는 **리포 밖**에 둔다 — 리포는 PUBLIC이고, 작업 트리에 없는 파일은 실수로도 커밋되지 않는다. `keytool`은 PKCS12로 만든다(JKS 마이그레이션 경고가 안 뜨는 게 정상이다). 스토어 비밀번호를 묻고 이어서 키 비밀번호를 물으면 **엔터를 쳐서 스토어와 같게 한다** — PKCS12는 둘을 다르게 쓰지 못한다.

이제 Gradle이 읽을 좌표 파일을 만든다. 비밀번호는 셸을 거치지 않는다 — 자리표시자로 파일을 만들고 에디터에서 채운다.

```bash
cd apps/mobile
cat > android/key.properties <<EOF
storePassword=CHANGE_ME
keyPassword=CHANGE_ME
keyAlias=cookmark-pilot
storeFile=$HOME/.cookmark/cookmark-pilot.jks
EOF
chmod 600 android/key.properties
```

에디터로 열어 `CHANGE_ME` 두 곳을 위에서 넣은 비밀번호로 바꾼다(둘 다 같은 값이다). `storeFile`은 `$HOME`이 이미 펼쳐진 절대 경로여야 한다.

마지막으로 커밋 표면에 새지 않았는지 확인한다.

```bash
git status --short
git check-ignore -v android/key.properties
# → android/.gitignore:12:key.properties   android/key.properties
```

`git status`에 `key.properties`나 `*.jks`가 보이면 **즉시 멈춘다**. 키스토어를 잃으면 같은 서명을 다시 만들 방법이 없고, 파일럿 도중 데이터를 보존하는 핫픽스가 영구히 불가능해진다. `~/.cookmark/`를 **비공개** 백업(외장 디스크 등)에 1부 둔다 — 리포·공개 드라이브 금지.

## 2. 툴체인 좌표 — 이 셸에서 계속 쓰는 경로들

```bash
export ANDROID_SDK="$HOME/Library/Android/sdk"
export ADB="$ANDROID_SDK/platform-tools/adb"      # PATH에 없다 — 절대 경로로 쓴다
export BT="$ANDROID_SDK/build-tools/36.1.0"       # apksigner · aapt2가 여기 산다
export APK="build/app/outputs/flutter-apk/app-release.apk"
cd apps/mobile && flutter --version && "$ADB" devices
```

`flutter doctor`가 `cmdline-tools`가 없다고 경고하지만 **빌드는 된다** — 없는 것은 라이선스 관리 도구뿐이고 SDK 라이선스는 이미 수락돼 있다([#134](https://github.com/woosung-dev/cookmark/issues/134) 실측). 같은 이유로 `apkanalyzer`도 없다 — §4의 검증은 `apksigner`와 `aapt2`로 한다.

## 3. 파일럿 APK — 명령 한 줄로 릴리스 서명 빌드

```bash
cd apps/mobile && flutter build apk --release --dart-define=COOKMARK_API_BASE=https://cookmark-woosungdevs-projects.vercel.app
```

**`--dart-define`을 빠뜨리면 앱이 조용히 죽는다.** 웹은 same-origin이라 빈 기본값으로 돌았지만 **네이티브에는 same-origin이 없다** — [#134](https://github.com/woosung-dev/cookmark/issues/134)가 "핵심 함정"으로 기록했다. 상대 경로 요청이 전부 실패하고 화면에는 영원히 도는 시머만 남는다. 정본 도메인은 `cookmark-woosungdevs-projects.vercel.app`이다 — **`cookmark.vercel.app`은 남의 프로젝트다**(Vercel 전역 네임스페이스).

`--split-per-abi`는 쓰지 않는다 — 단일 fat APK 하나가 실기기(arm64)와 에뮬레이터를 함께 덮는다. 산출물은 `apps/mobile/$APK`다. 첫 빌드는 R8 내려받기와 NDK 초기화 때문에 5~10분 걸리고 두 번째부터 짧다.

`android/key.properties`가 없으면 **여기서 즉시 죽는 게 정상이다**. 그때는 §1로 돌아간다.

## 4. 산출물 확인 — 서명·권한·백업·라벨을 APK에서 직접 읽는다

서명과 매니페스트는 빌드 산출물의 성질이라 Flutter 테스트가 닿지 못한다. 새 키로 처음 뽑았을 때 한 번은 눈으로 본다.

```bash
"$BT/apksigner" verify --print-certs --verbose "$APK"
"$BT/aapt2" dump badging "$APK" | grep -E "^package|application-label|uses-permission"
"$BT/aapt2" dump permissions "$APK"
"$BT/aapt2" dump xmltree "$APK" --file AndroidManifest.xml | grep -i allowBackup
```

기대값은 넷이다.

- `Signer #1 certificate DN: CN=cookmark pilot, …` 와 `Verified using v2 scheme …: true` — §1에서 만든 키로 서명됐다.
- `package: name='dev.woosung.cookmark' versionCode='N'` 과 `application-label:'cookmark'`.
- 권한은 **`android.permission.INTERNET` 하나뿐**이다. `CAMERA`·`READ_MEDIA_IMAGES`·`READ_EXTERNAL_STORAGE`가 보이면 플러그인이 주입한 것이니 멈추고 [#131](https://github.com/woosung-dev/cookmark/issues/131)로 돌아간다 — 선언만으로 런타임 권한 다이얼로그가 강제되어 온보딩에 승인 단계가 낀다.
- `android:allowBackup(0x0101000d)=(type 0x12)0x0` — `0x0`이 false다.

## 5. 배우자 기기 설치 — 카톡으로 보내고 파운더가 직접 깐다

**배우자가 설치를 하지 않는다. 파운더가 기기를 받아 직접 깐다.** 사이드로드 경고 화면과 Play Protect 대화상자는 "실험 중인 앱"이라는 신호라 단일맹검을 깬다(ADR-0004 · [#135](https://github.com/woosung-dev/cookmark/issues/135)). 파운더가 그 화면들을 흡수하면 배우자에게 앱은 그냥 홈 화면에 있는 앱 하나다. 배우자에게 하는 설명 문구는 [#146](https://github.com/woosung-dev/cookmark/issues/146) · [#65](https://github.com/woosung-dev/cookmark/issues/65)의 온보딩 스크립트를 따른다 — 이 절은 손가락 순서만 다룬다.

1. APK를 카톡 파일 전송으로 배우자 기기에 보낸다(전달 경로 결정 = [#132](https://github.com/woosung-dev/cookmark/issues/132)).
2. 기기에서 파일 앱 → 다운로드 → `app-release.apk`를 탭한다.
3. "알 수 없는 앱 설치"를 **그 앱에만** 1회 허용한다.
4. Play Protect "확인되지 않은 앱" 경고에서 **자세히 → 무시하고 설치**를 누른다.
5. 홈 화면에 `cookmark` 아이콘이 있는지 확인한다.
6. 첫 실행에서 사진 1장을 관통시켜 네트워크가 살아 있는지 본다(§3의 `--dart-define`이 여기서 증명된다).

파운더 기기와 에뮬레이터는 USB로 더 짧다.

```bash
"$ADB" install -r "$APK"
```

## 6. 핫픽스 재배포 — versionCode 범프 → 재빌드 → 덮어쓰기 설치

파일럿 posture는 코드 프리즈가 아니라 **열린 핫픽스 + 'hotfix' 개입 로그**다([#133](https://github.com/woosung-dev/cookmark/issues/133)). 데이터 보존은 서명이 같다는 사실 하나에 달려 있다.

1. `apps/mobile/pubspec.yaml`의 `version: 1.0.0+N`에서 **`+N`을 1 올리고 커밋한다.** 이게 `versionCode`다. 범프하지 않으면 OS가 설치를 업데이트로 보지 않거나 아예 거부한다. 번호는 git에 남아야 파운더 머신 사이에서 흘러가지 않는다 — 임시로만 덮으려면 `flutter build apk --release --build-number=N`을 쓴다.
2. §3의 빌드 한 줄을 그대로 다시 돌린다.
3. **앱을 지우지 않고 덮어쓴다.** `"$ADB" install -r "$APK"`, 배우자 기기는 새 APK를 다시 보내 탭한다(기존 앱 "업데이트"로 뜨는 게 정상이다).
4. 앱을 열어 레시피 북이 그대로인지 눈으로 확인한다. 기계적 확인은 아래 한 줄이다 — `firstInstallTime`이 **그대로**고 `lastUpdateTime`만 바뀌면 OS가 업데이트로 처리했다는 뜻이고 데이터 디렉터리는 보존됐다.

```bash
"$ADB" shell dumpsys package dev.woosung.cookmark | grep -E "versionCode|firstInstallTime|lastUpdateTime"
```

5. 개입을 'hotfix' 세그먼트로 관찰 일지에 기록한다 — 시각·무엇이 깨졌나·무엇을 바꿨나·어느 기기([#133](https://github.com/woosung-dev/cookmark/issues/133)). 분석 시 '깨진 앱 구간'과 '고친 앱 구간'을 분리하는 데 쓴다.

## 함정

- **`릴리스 서명 키가 없다`로 빌드가 즉시 죽는다** — `apps/mobile/android/key.properties`가 없다 → §1을 1회 실행한다. 그 파일은 커밋되지 않으므로 **새 클론·새 머신마다 다시 필요하다**. 조용한 디버그 서명 폴백은 의도적으로 막혀 있다.
- **설치가 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`로 거부된다** — 이미 깔린 앱과 서명이 다르다(디버그 키로 깔았던 기기다) → 파일럿 **시작 전**이면 지우고 릴리스 서명본으로 다시 깐다. **파일럿 중이면 지우지 말고 멈춘다** — 지우는 순간 2주치가 사라진다. 실패한 것은 설치이지 데이터가 아니다.
- **인식이 영원히 로딩이고 네트워크가 조용히 죽는다** — `--dart-define=COOKMARK_API_BASE`를 빠뜨렸다 → §3 한 줄을 통째로 복사한다.
- **재설치했는데 앱이 "처음 실행"처럼 보인다** — 앱을 지우고 깔았거나 `versionCode`를 안 올렸다 → §6 순서를 지킨다.
- **keytool이 비밀번호를 두 번 묻는데 다르게 넣었다** — PKCS12는 스토어와 키 비밀번호가 같아야 한다 → 키 비밀번호에서 엔터를 친다. `key.properties`의 두 값도 같다.
- **`key.properties에 storeFile 가 없다`로 죽는다** — 자리표시자를 안 채웠거나 키 이름에 오타가 있다 → §1의 4줄을 그대로 쓴다.
- **키스토어를 잃었다** — 같은 서명을 다시 만들 방법이 없다 → 파일럿 중 데이터 보존 핫픽스가 불가능해진다. §1의 백업을 미리 해둔다. **리포·공개 드라이브 금지.**
- **`git status`에 `key.properties`나 `*.jks`가 보인다** — 경로 착오로 gitignore가 안 먹었다 → 커밋하지 말고 멈춘다. 이미 밀었다면 키스토어를 폐기하고 §1부터 다시 만든다. 리포는 PUBLIC이다.
- **`flutter doctor`가 cmdline-tools 없다고 경고한다** — 라이선스 도구만 없다 → 무시한다([#134](https://github.com/woosung-dev/cookmark/issues/134) 실측).
- **첫 릴리스 빌드가 5~10분 걸린다** — R8 내려받기·축소와 NDK 초기화가 처음 한 번 돈다 → 실패로 오해하지 않는다.
- **에뮬레이터가 `INSTALL_FAILED_NO_MATCHING_ABIS`를 낸다** — 스플릿 APK를 만들었다 → `--split-per-abi`를 쓰지 않는다. 기본 fat APK가 arm64를 포함한다.
