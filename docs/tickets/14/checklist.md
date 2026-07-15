# 티켓 #14 체크리스트 — 코어 관통(사진→인식→재료 체크리스트) + Web 빌드 배포

부모 스펙 #13. 이 티켓만 이번 세션 범위(#15~#22는 후속).

## 0. 준비
- [x] 브랜치 `feat/14-core-tracer` 생성 (main 기준)
- [x] Flutter Web 스캐폴드 생성 (`flutter create --platforms web`)
- [x] 의존성 추가 — image_picker · image · http · shared_preferences · integration_test
- [x] 계획·체크리스트·컨텍스트 노트 작성

## 1. 문서 정합 (선행 — CLAUDE.md "UI 만들기 전 DESIGN.md 갱신")
- [ ] DESIGN.md §4·§7의 **하단 탭바** → ADR-0001의 **헤더 링크 1개**로 정정
      → 검증: DESIGN.md에 "탭바" 잔존 0건, ADR-0001과 모순 없음

## 2. 도메인 모델 (유닛 TDD)
- [ ] `Confidence` 3단 + `Ingredient` — confidence→초기 체크 상태 산식(ADR-0003 한 몸)
      → 검증: high=체크 / medium=체크 / low=해제 유닛 통과
- [ ] 이벤트 모델 — 유형·타임스탬프·JSON 직렬화(export 대비)
      → 검증: 라운드트립 유닛 통과

## 3. 스토리지 모듈 (단일 경계 — 위젯에서 직접 호출 금지)
- [ ] `AppStorage` — 이벤트 append / 읽기, 세션 상태 저장, SharedPreferences 백엔드
      → 검증: append 후 재읽기 유닛 통과(mock initialValues)

## 4. LLM 경계 (유일한 seam)
- [ ] `IngredientRecognizer` 추상 + `RecognitionResult`(재료·지연·토큰·추정 원가)
- [ ] `GeminiProxyRecognizer` — 서버리스 프록시 POST, 모델명 환경설정 주입
- [ ] `FakeRecognizer` — P1 실측 닮은 fixture(high/medium/low 혼합 + 뭉뚱그림 "반찬통")
      → 검증: 페이크 주입 시 결정적 출력 유닛 통과

## 5. 서버리스 프록시 (Vercel)
- [ ] `api/recognize.js` — GEMINI_API_KEY 서버 보관, 이미지 수신→Gemini 호출→{ingredients, usage} 회신
- [ ] 모델명 `GEMINI_MODEL` 환경변수 주입 (기본 gemini-3.1-flash-lite)
      → 검증: 로컬에서 실키로 실호출 1회 성공(재료 배열 + 토큰 수 회신)

## 6. 이미지 리사이즈
- [ ] 클라이언트 768px 리사이즈 후 전송
      → 검증: 큰 이미지 입력 → 최대 변 768 유닛 통과

## 7. 화면 (단일 페이지 상태 기계 — #14 구간)
- [ ] 앱 셸 — 헤더 + 레시피 북 링크 1개(탭바 없음)
- [ ] 온보딩/업로드 존 → 로딩 → 체크리스트 / 에러
- [ ] 로딩: 사진 위 스캔 시머 + 체크박스 스켈레톤 + 단계식 문구(0~3s / 3~10s / 10s 취소 등장 / 30s 타임아웃)
- [ ] 체크리스트: high 체크 / medium 체크+물음표 점 / low 해제 "확실하지 않아요" 흐린 그룹
      → 검증: E2E가 3단 초기 상태를 화면에서 확인

## 8. E2E (정본)
- [ ] `integration_test` — 페이크 주입, 업로드→로딩→체크리스트 관통
- [ ] 이벤트 로그에 사진 업로드·인식 완료(지연·토큰·원가)가 남고 새로고침 후 유지
      → 검증: Web 타깃 실행으로 결정적 통과

## 9. 마감
- [ ] `flutter analyze` 무이슈
- [ ] `flutter test` 전체 통과
- [ ] `flutter build web` 성공
- [ ] Vercel 배포 → 모바일 브라우저 URL에서 실사진 관통(실 Gemini 호출)
- [ ] /code-review
- [ ] 커밋 · PR

## 이월 (이 티켓 밖 — 기록만)
- DESIGN.md §7 "제휴 담기"(어필리에이트 = Out of Scope 2기), "제안 상세 바텀시트"·매칭률 → ADR-0001 화면전환 0회와 충돌. 티켓 #18에서 정리 필요.
