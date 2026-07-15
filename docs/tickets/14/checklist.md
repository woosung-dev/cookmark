# 티켓 #14 체크리스트 — 코어 관통(사진→인식→재료 체크리스트) + Web 빌드 배포

부모 스펙 #13. 이 티켓만 이번 세션 범위(#15~#22는 후속).

## 0. 준비
- [x] 브랜치 `feat/14-core-tracer` 생성 (main 기준)
- [x] Flutter Web 스캐폴드 생성 (`flutter create --platforms web`)
- [x] 의존성 추가 — image_picker · image · http · shared_preferences · integration_test
- [x] 계획·체크리스트·컨텍스트 노트 작성

## 1. 문서 정합 (선행 — CLAUDE.md "UI 만들기 전 DESIGN.md 갱신")
- [x] DESIGN.md §4·§7의 **하단 탭바** → ADR-0001의 **헤더 링크 1개**로 정정
      → 검증: DESIGN.md에 "탭바" 잔존 0건, ADR-0001과 모순 없음

## 2. 도메인 모델 (유닛 TDD)
- [x] `Confidence` 3단 + `Ingredient` — confidence→초기 체크 상태 산식(ADR-0003 한 몸)
      → 검증: high=체크 / medium=체크 / low=해제 유닛 통과
- [x] 이벤트 모델 — 유형·타임스탬프·JSON 직렬화(export 대비)
      → 검증: 라운드트립 유닛 통과

## 3. 스토리지 모듈 (단일 경계 — 위젯에서 직접 호출 금지)
- [x] `AppStorage` — 이벤트 append / 읽기, 세션 상태 저장, SharedPreferences 백엔드
      → 검증: append 후 재읽기 유닛 통과(mock initialValues)

## 4. LLM 경계 (유일한 seam)
- [x] `IngredientRecognizer` 추상 + `RecognitionResult`(재료·지연·토큰·추정 원가)
- [x] `GeminiProxyRecognizer` — 서버리스 프록시 POST, 모델명 환경설정 주입
- [x] `FakeRecognizer` — P1 실측 닮은 fixture(high/medium/low 혼합 + 뭉뚱그림 "반찬통")
      → 검증: 페이크 주입 시 결정적 출력 유닛 통과

## 5. 서버리스 프록시 (Vercel)
- [x] `api/recognize.mjs` — GEMINI_API_KEY 서버 보관, 이미지 수신→Gemini 호출→{ingredients, usage} 회신
- [x] 모델명 `GEMINI_MODEL` 환경변수 주입 (기본 gemini-3.1-flash-lite)
      → 검증: 로컬에서 실키로 실호출 1회 성공(재료 배열 + 토큰 수 회신)

## 6. 이미지 리사이즈
- [x] 클라이언트 768px 리사이즈 후 전송
      → 검증: 큰 이미지 입력 → 최대 변 768 유닛 통과

## 7. 화면 (단일 페이지 상태 기계 — #14 구간)
- [x] 앱 셸 — 헤더 + 레시피 북 링크 1개(탭바 없음)
- [x] 온보딩/업로드 존 → 로딩 → 체크리스트 / 에러
- [x] 로딩: 사진 위 스캔 시머 + 체크박스 스켈레톤 + 단계식 문구(0~3s / 3~10s / 10s 취소 등장 / 30s 타임아웃)
- [x] 체크리스트: high 체크 / medium 체크+물음표 점 / low 해제 "확실하지 않아요" 흐린 그룹
      → 검증: E2E가 3단 초기 상태를 화면에서 확인

## 8. E2E (정본)
- [x] `integration_test` — 페이크 주입, 업로드→로딩→체크리스트 관통
- [x] 이벤트 로그에 사진 업로드·인식 완료(지연·토큰·원가)가 남고 새로고침 후 유지
      → 검증: Web 타깃 실행으로 결정적 통과

## 9. 마감
- [x] `flutter analyze` 무이슈
- [x] `flutter test` 전체 통과
- [x] `flutter build web` 성공
- [ ] **(이월)** Vercel 배포 → 모바일 브라우저 URL에서 실사진 관통 — 로그인 필요, 다음 세션
- [x] 실사진 관통을 프록시 핸들러+실키로 로컬 검증(7건 인식·1.94s·$0.00054)
- [x] /code-review — 2축 리뷰 반영 완료(모델 귀속·30s 타임아웃 경계·글로서리·죽은 API 제거)
- [x] 커밋
- [ ] PR

## 이월 (이 티켓 밖 — 기록만)
- **배포**: Vercel 로그인 필요 → #14의 AC 2건(배포된 URL 관통·실 Gemini 호출)이 열린 채. D0 게이트.
- **DESIGN.md §7 잔여 충돌** → 티켓 #18 착수 전 정리:
  - "제휴 담기"(어필리에이트 = 스펙 #13 Out of scope, 2기)
  - "제안 상세: 바텀시트"·매칭률 → ADR-0001 "화면 전환 0회"·G1 #8 확정 카드 구성에 없음
  - 이번 세션에 같은 종류(탭바·medium 배지) 2건을 정정했다 — 화면 층위 규정이 DESIGN.md에 남아 있는 한 재발한다.
- **세션 복원**: 배너 없는 절반 구현으로 남음 → #15·#19에서 "다시 제안" 배너·stale 플래그와 함께 완결.
