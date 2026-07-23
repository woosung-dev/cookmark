# #146 운영 문서 네이티브 치환 — 체크리스트

티켓 정본은 [#146](https://github.com/woosung-dev/cookmark/issues/146), 상류는 스펙 [#140](https://github.com/woosung-dev/cookmark/issues/140) ④(지도 [#129](https://github.com/woosung-dev/cookmark/issues/129) · 온보딩 정본 [#135](https://github.com/woosung-dev/cookmark/issues/135) resolution · 핫픽스 [#133](https://github.com/woosung-dev/cookmark/issues/133) · 단일맹검 ADR-0004). 결정 로그는 context-notes.md.

목표 한 줄 — **D0(2026-07-22) 저녁 파운더가 읽는 운영 문서가 네이티브 APK가 실제로 할 동작을 말한다. 웹 절차(사이트 데이터 삭제·재import·카톡 URL 공유)를 네이티브(제스처·초기화 버튼·APK 파일 전송)로 치환하고, "이벤트 1이 정상"을 "이벤트 0이 정상"으로 반전한다.**

## 산출물 (git 파일 1 + GitHub 이슈 변경 3)

### A. `docs/pilot/d0-readiness.md` (git/PR)

- [x] 5곳의 `?debug` 트리거 서술 → 앱바 "냉파" 타이틀 롱프레스로 치환(#143 커밋 `f90e902`가 코드에서 제거)
- [x] **"이벤트 1이 정상" → "이벤트 0이 정상" 반전** + 사유 한 줄(재import 소멸). 코드 정본 = `main_controller.dart` `_recordEpoch`(초기화 후 이벤트 0 보증)
- [x] 초기화 절차를 네이티브 2단계로(롱프레스 → 초기화 버튼 → 확인 다이얼로그, 레시피 보존)
- [x] 배우자 기기 "확인 후 다시 롱프레스로 닫기" 한 줄(#146 코멘트 — 자동 닫기 미채택)
- [x] 정본 URL은 프록시 엔드포인트로 유지(#130)

### B. 이슈 #41 본문 (`gh issue edit`)

- [x] 절차 5단계 → 2단계(`복사 → 카톡 보관 → 사이트 데이터 삭제 → 재열기 → 붙여넣기` → `제스처 → 초기화 버튼`)
- [x] "앱에 초기화 UI는 없다" 전제 삭제(#144가 만들었다). 사이트 데이터 삭제·재import 단계 통째 삭제
- [x] **불변식 반전 굵게** — "이벤트 1이 정상" → "이벤트 0이 정상" + 왜(재import 소멸) 한 줄
- [x] 배우자 기기 동일 적용 + "기록 정리"로만 설명(계측 비공개 유지, ADR-0004) + 롱프레스로 다시 닫기

### C. 이슈 #65 본문 (`gh issue edit`)

- [x] ④ 배우자 온보딩 → #135 resolution 갱신안 그대로 치환(파운더 hands-on 설치·대면 import)
- [x] ② 기록 초기화 → 네이티브 2단계 + "이벤트 0이 정상" 반전
- [x] ③ 재배포 확인 → APK 빌드·서명 확인(Vercel 프리빌드는 배포 경로 아님)
- [x] ① 관통 스모크에 실기기 전용 항목 편입(카메라/picker · 외부 브라우저 · 실 사진 인식 · 실 폰 레이아웃 · 카톡 설치 #132 · Play Protect)
- [x] ① 스모크에 오형식 200 하드닝 확인(#142) 편입
- [x] 기계적 치환(홈 화면 추가 소멸 · 인앱 브라우저 문구 삭제 · 권한 팝업 없음 · 정본 URL 유지)

### D. 이슈 #9 (`gh issue comment` — 본문 무편집)

- [x] 본문 고치지 않음(2026-07-13 규약으로 보존)
- [x] 정정 코멘트 — 네이티브 치환분(#135 resolution · ADR-0011)을 가리킴
- [x] 관찰 일지 포맷에 'hotfix' 개입 유형 포함(#133) — 시각 · 무엇이 깨졌나 · 무엇을 바꿨나 · 어느 기기

## 검증

- [x] `docs/pilot/d0-readiness.md`의 **live 절차에 `?debug` 트리거 지시 0** — 남은 `?debug`·"이벤트 1" 언급 2곳은 제거·반전을 **설명하는** 서술뿐(잔존이 아니다)
- [x] #41·#65 본문에 웹 절차(사이트 데이터 삭제·재import·카톡 URL·홈 화면 추가) 잔존 0
- [x] `/code-review`(d0-readiness.md 변경) — Standards·Spec 양축
- [x] 메모리 갱신([[cookmark-issue41-reset-rehearsal]] 반전 반영)

## 범위 밖 (경계)

- ADR-0011 신규 작성 + AGENTS.md·coding-standards.md·CONTEXT.md = **#145**(형제 티켓, 이 티켓 아님)
- 코드 변경 없음(순수 문서)
