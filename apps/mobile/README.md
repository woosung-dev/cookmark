# apps/mobile — 냉파 Flutter 앱

파일럿 MVP(질문 검증기). 규약은 루트 `AGENTS.md`, Flutter 아키텍처 정본은 `.claude/rules/mobile.md`(gitignored·규범), 측정 순도 경계 규칙(단일 스토리지·단일 LLM seam·화면 구조)은 ADR이 우선한다.

```bash
flutter pub get
dart format .
flutter analyze --fatal-infos
flutter test                    # 유닛·위젯
bash scripts/e2e.sh             # E2E (검증의 정본) — chromedriver 필요
flutter run -d chrome           # 로컬 실행 (Web 우선 타깃)
flutter build web               # 배포 산출물 → build/web (vercel.json outputDirectory)
flutter build apk --release --dart-define=COOKMARK_API_BASE=https://cookmark-woosungdevs-projects.vercel.app   # 파일럿 APK
```

주의 — `test/architecture/navigation_test.dart`는 cwd 의존(`Directory('lib')`)이라 반드시 이 디렉토리에서 `flutter test`를 실행한다. 배포는 리포 루트에서 수동 프리빌드(`vercel build` → `vercel deploy --prebuilt`)만 — main 자동배포 차단(#57).

네이티브 파일럿 APK 절차(키스토어 1회 생성·빌드·기기 설치·핫픽스 재배포)는 `docs/pilot/native-apk-runbook.md`가 정본이다. 릴리스 빌드는 `android/key.properties`가 없으면 **실패한다** — 조용한 디버그 서명 폴백을 막은 의도된 동작이다([#141](https://github.com/woosung-dev/cookmark/issues/141)).
