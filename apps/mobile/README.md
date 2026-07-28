# apps/mobile — 냉파 Flutter 앱

파일럿 MVP(질문 검증기). 규약은 루트 `AGENTS.md`, Flutter 아키텍처 정본은 `.claude/rules/mobile.md`(gitignored·규범), 측정 순도 경계 규칙(단일 스토리지·단일 LLM seam·화면 구조)은 ADR이 우선한다.

```bash
flutter pub get
dart format .
flutter analyze --fatal-infos
flutter test                    # 유닛·위젯
bash scripts/e2e.sh             # E2E (검증의 정본) — chromedriver 필요
CHROMEDRIVER_PORT=4455 bash scripts/e2e.sh   # 병렬 워크트리에서 동시 실행할 때 (기본 4444)
flutter run -d chrome           # 로컬 실행 (Web 우선 타깃)
flutter build web               # 배포 산출물 → build/web (vercel.json outputDirectory)
flutter build apk --release --dart-define=COOKMARK_API_BASE=https://cookmark-woosungdevs-projects.vercel.app   # 파일럿 APK (main.dart · 프록시)
flutter build web -t lib/main_api_cutover.dart --dart-define=COOKMARK_SERVER_BASE=<apps/api 주소> --dart-define=COOKMARK_REGISTER_KEY=<등록 키>   # 컷오버 빌드 web (로컬 스모크)
flutter build apk --release -t lib/main_api_cutover.dart --dart-define=COOKMARK_SERVER_BASE=<Cloud Run URL> --dart-define=COOKMARK_REGISTER_KEY=<등록 키>   # 코호트 APK (apps/api · flip)
```

**백엔드 주소는 이름이 갈려 있다**(#164) — 프록시(`main.dart`)는 `COOKMARK_API_BASE`, `apps/api`(컷오버·스파이크 엔트리)는 `COOKMARK_SERVER_BASE`다. 이름을 바꿔 짚어도 빌드는 성공하고 실패만 조용해지므로 재사용하지 않는다. 컷오버 빌드에서 `COOKMARK_SERVER_BASE`가 비면 프록시 조립으로 폴백한다(절차 정본은 **로컬 web 스모크 = `docs/pilot/api-cutover-smoke.md`**, **코호트 APK = `docs/pilot/flip-runbook.md`**).

**`COOKMARK_REGISTER_KEY`는 서버의 같은 이름 시크릿과 값이 같아야 한다**([#168](https://github.com/woosung-dev/cookmark/issues/168)) — 앱이 부팅 경로에서 `POST /api/v1/auth/device`로 익명 계정을 받고, 그 토큰이 기기 보안 저장소에 산다(ADR-0012). 로그인 화면·탭·설정 항목은 없다. 키가 비거나 틀리면 서버가 **403**을 내고 인라인 실패 카드로 뜬다 — 재시도로 고쳐지지 않으니 APK를 다시 낸다. 세션 토큰을 빌드에 박던 `COOKMARK_SESSION_TOKEN`은 은퇴했다(1빌드=1계정이라 코호트 배포에서 무너진다).

주의 — `test/architecture/`의 트립와이어들은 cwd 의존(`Directory('lib')`)이라 반드시 이 디렉토리에서 `flutter test`를 실행한다. 배포는 리포 루트에서 수동 프리빌드(`vercel build` → `vercel deploy --prebuilt`)만 — main 자동배포 차단(#57).

네이티브 파일럿 APK 절차(키스토어 1회 생성·빌드·기기 설치·핫픽스 재배포)는 `docs/pilot/native-apk-runbook.md`가 정본이다. 릴리스 빌드는 `android/key.properties`가 없으면 **실패한다** — 조용한 디버그 서명 폴백을 막은 의도된 동작이다([#141](https://github.com/woosung-dev/cookmark/issues/141)).

**코호트 APK(`apps/api`를 싣는 flip 산출물)의 절차 정본은 `docs/pilot/flip-runbook.md`다**([#169](https://github.com/woosung-dev/cookmark/issues/169)) — 빌드 명령·관통 스모크·배포 채널 검증·되돌림·합류 이전. 키스토어와 설치 손가락 순서는 위 네이티브 런북을 그대로 쓴다.
