# #141 체크리스트 — 네이티브 파일럿 빌드 성립

## 랜딩

- [x] 브랜치 `feat/141-native-pilot-build` (main 기준, 이 워크트리)
- [x] 스파이크 `android/` 트리 19개 경로 한정 checkout (cherry-pick 아님)
- [x] `main_native_smoke.dart` 미랜딩 확인 (`git ls-files` 비어 있음)
- [x] `.metadata`에 `android` 항목 **추가** — `web` 유지 (스파이크는 치환했다, 결함)
- [x] `key.properties` gitignore 확인 (`android/.gitignore:12`)

## 매니페스트

- [x] `INTERNET`이 **메인** 매니페스트에 있고 삭제 금지 주석 유지
- [x] `android:allowBackup="false"` + 한국어 사유 주석
- [x] 권한 추가 없음 (`CAMERA`·`READ_MEDIA_IMAGES`·`READ_EXTERNAL_STORAGE`)
- [x] 라벨 `cookmark` · 애플리케이션 ID `dev.woosung.cookmark` 유지

## 서명 배선

- [x] `key.properties`에서 좌표·비밀번호를 읽어 릴리스 `signingConfig`에 연결
- [x] 프로퍼티 파일 부재 시 **릴리스만** 실패 (`gradle.startParameter.taskNames`)
- [x] 조용한 디버그 서명 폴백 없음
- [x] 부정 테스트 — 키 없이 `--release` → 한국어 GradleException, 2초, APK 미생성
- [x] 양성 대조 — 키 없이 `--debug` → 성공 (23초)

## 문서

- [x] `docs/pilot/native-apk-runbook.md` — §1 키스토어 · §2 툴체인 · §3 빌드 · §4 산출물 확인 · §5 배우자 기기 설치 · §6 핫픽스 · 함정
- [x] 빌드 명령에 `COOKMARK_API_BASE` 주입 (복붙 한 줄)
- [x] `versionCode` 매 빌드 범프가 §6에 절차로 박힘
- [x] `.vercelignore` — Gradle 형제 디렉터리 제외 + 유지보수 주석
- [x] `apps/mobile/README.md` — APK 명령 1줄 + 런북 포인터

## 게이트

- [x] `dart format` (88 files, 0 changed)
- [x] `flutter analyze --fatal-infos` (No issues)
- [x] `flutter test` (403 passed)

## HITL · 실기기 검증 (파운더)

- [ ] 파운더가 런북 §1로 키스토어 + `key.properties` 생성
- [ ] 릴리스 APK 빌드
- [ ] `apksigner`/`aapt2`로 서명·`allowBackup`·`INTERNET` 단독·라벨 확인
- [ ] 에뮬레이터 설치 + 레시피 심기
- [ ] 핫픽스 루프 리허설 — `versionCode` 범프 → 재설치 → 데이터 생존 (`firstInstallTime` 불변)

## 마무리

- [ ] 시맨틱 커밋 4분할
- [ ] `/code-review`
- [ ] PR
