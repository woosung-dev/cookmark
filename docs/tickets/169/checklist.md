# #169 체크리스트 — flip 런북 + `infra/README` 운영 절차

티켓 정본은 [#169](https://github.com/woosung-dev/cookmark/issues/169), 상류는 스펙 [#161](https://github.com/woosung-dev/cookmark/issues/161) §H·§K·§L(지도 [#153](https://github.com/woosung-dev/cookmark/issues/153) CLOSED · 게이트 [#157](https://github.com/woosung-dev/cookmark/issues/157) · 되돌림 [#158](https://github.com/woosung-dev/cookmark/issues/158) · 데이터 경계 [#159](https://github.com/woosung-dev/cookmark/issues/159) · 프록시 폐기 [#160](https://github.com/woosung-dev/cookmark/issues/160))이고 결정 정본은 [ADR-0012](../../adr/0012-anonymous-device-registration.md). 결정 로그는 `context-notes.md`.

목표 한 줄 — **파운더가 문서만 보고 flip 게이트를 통과시킬 수 있다.** 코드 0줄.

범위 경계 — **문서만.** 에이전트가 절차를 쓰고 파운더가 실행한다([#141](https://github.com/woosung-dev/cookmark/issues/141)과 같은 역할 분담). 실행은 [#170](https://github.com/woosung-dev/cookmark/issues/170), 프록시 은퇴·엔트리 통합은 [#171](https://github.com/woosung-dev/cookmark/issues/171).

## 파운더 확정 결정

- [x] **런북 경로 = `docs/pilot/flip-runbook.md`** — 기존 런북 2개와 같은 폴더. 상호 링크가 상대경로라 무마찰이고 런북이 한 곳에 모인다
- [x] **게이트 A~G는 "게이트 → 절 매핑 표"만** — 판정 문구는 #170이 정본. 복제 0이라 갈라지지 않는다
- [x] **`AGENTS.md`·`apps/mobile/README.md`에 코호트 빌드 한 줄씩 추가** — 네이티브 컷오버 빌드 명령이 리포 어디에도 없었다

## 산출물

- [x] **신규 런북** — `docs/pilot/flip-runbook.md`. 서두 3단(정본 선언 · **여기 없는 것** · 게이트 매핑 표) + 8절 + 함정
  - [x] §1 좌표 — `REGION`·`SERVICE`·`URL`·`REGISTER_KEY`. **등록 키를 Secret Manager에서 직접 읽어** 서버와 APK가 같은 값임을 구조로 보장(손으로 옮기면 오타가 403으로만 드러나고 403은 화면에서 서버 장애와 구별되지 않는다)
  - [x] §2 코호트 APK — 빌드 한 줄 + **누락 시 무엇이 죽나 표 3행**(`-t` · `COOKMARK_SERVER_BASE` · `COOKMARK_REGISTER_KEY`). 셋 다 빌드 성공·정상 실행이고 실패만 조용하다. `main_api_spike.dart` 금지 사유. `versionCode` 번호 공간 공유
  - [x] §3 관통 스모크 — 서버 curl(등록·403·401) + **실 Gemini 텍스트 1콜** · 에뮬레이터 관통 · CRUD 1바퀴 · **콜드/웜 지연 4행 표**
  - [x] §4 구멍 — health 정적 dict 자백 인용 · deep health 미승격 사유(Neon 유휴 정지 무력화 → 월 $0 파괴) · E2E는 페이크 3개 · **확인 항목 1건**(같은 Gemini 키 → 쿼터 공유)
  - [x] §5 배포 채널 — v1 → 데이터 → `versionCode`+1 → v2 → `dumpsys` 확인. 서명 동일이 유일한 성립 조건
  - [x] §6 되돌림 2단 — 3행 표. 명령은 `infra/README` §8·§9 포인터(복제 0). 다운타임 숫자 미기재 사유. **인지 경로 = 실패 문구 + 카톡뿐**
  - [x] §7 코호트 배포 — **기대치 고지 문안**(그대로 복사) · 빈 계정 시작·이전 없음 · 파운더만 알 것 3건 · **되돌릴 수 없는 선** 표시
  - [x] §8 합류 — 5단계 + ⚠️ **④를 어떤 저장보다 먼저**(순서의 이유) + 화면 손가락 순서 + 발동 확인이 #171의 하한
  - [x] 함정 10건 — 전부 실물 확인된 증상
- [x] **`infra/README.md` §8 신설** — 리비전 롤백. `revisions list` → `update-traffic --to-revisions` → health → `--to-latest`. ⚠️ 3건(**스키마 변경이 얽히면 무효** · 옛 리비전은 옛 시크릿 값 · **다음 배포에 핀이 풀린다**)
- [x] **`infra/README.md` §9 신설** — 킬 스위치 기록. Vercel env에서 Gemini 키 제거 → 산 채로 500. 기각된 앱↔백엔드 전환 스위치와 다른 물건 · `apps/api` 무영향(저장소가 다르다)이나 쿼터는 공유
- [x] **`AGENTS.md`** 명령 블록 — 코호트 APK 빌드 한 줄 + 런북 포인터
- [x] **`apps/mobile/README.md`** — 코호트 APK 한 줄 + 런북 정본 포인터. 기존 컷오버 줄은 "web(로컬 스모크)"로 명시
- [x] **내가 낡게 만든 문서 2곳 정정** — `native-apk-runbook.md`("컷오버 절차는 api-cutover-smoke가 정본"이 절반만 참이 됐다) · `api-cutover-smoke.md`(로컬 전용임과 배포 스모크의 정본을 명시)

## 검증

- [x] 식별자 대조 — `cookmark-api`·`asia-northeast3`·라우트 4종·dart-define 3종·엔트리 파일명·`dev.woosung.cookmark`·`emptyServerBook`
- [x] 링크 정합 — 상대경로가 실재 파일을 가리킨다
- [x] 빌드 명령 실행 검증 — 자리표시자로 1회
- [x] 무손상 스모크 — `dart format --set-exit-if-changed` · `flutter analyze` · `flutter test`
- [x] AC 12항목 문구 스캔
- [x] `/code-review` — Standards·Spec 두 축. **Spec 축이 하드 결함 1건 적발**(§3.3의 CRUD 증거 근거가 거짓 — 깨끗한 기기에선 가드가 구조적으로 발화하지 않는다). 자체 재독으로 2건 더(§4 "배포 green" 과장 · 함정 403 분기의 처방 역전). 반영 내역은 `context-notes.md`
- [x] 커밋

## 표면화 — 고치지 않은 것

- **`d0-readiness.md`의 정본 URL 블록이 여전히 프록시를 가리킨다** — 지금은 참이다(파일럿 2대가 프록시 빌드다). 은퇴 표기는 합류 시점에야 참이라 **#171 몫**이다(ADR-0012 「살아 있는 운영 문서의 갱신은 flip·합류 시점」).
- **루트 `checklist.md`·`context-notes.md`가 #145에 멈춰 있다** — #162·#167·#168이 전부 `docs/tickets/<N>/`에만 썼고 이 티켓도 같다. 그 두 파일의 처분은 이 티켓의 범위가 아니다.
- **`/api/v1/migration/recipes` 경로를 런북에 안 적었다** — 파운더가 직접 칠 일이 없고(앱의 「가져오기」가 부른다), 적으면 손으로 호출해도 된다고 읽힌다. 계약 정본은 `contracts/openapi.yaml`이다.
- **`min-instances`를 1로 올리는 절차를 안 적었다** — §3.4가 그 결정의 **입력**을 만들 뿐이고 결정은 실측 후에 난다. 지금 적으면 측정 전에 답이 정해진 것처럼 읽힌다.
- **하이드레이트 가드의 이벤트 3키가 런북 §3.3과 함정에 둘 다 있다** — 의도다. 함정은 증상으로 찾아오는 색인이라 검색어가 거기 있어야 하고, 같은 파일 안이라 갈라질 표면이 아니다.

자세한 결정 근거는 `context-notes.md`.
