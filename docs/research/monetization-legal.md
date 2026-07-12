# 수익화·법적 리스크 — freemium 벤치마크와 레시피 저장의 저작권 경계

> wayfinder 티켓 [#5](https://github.com/woosung-dev/cookmark/issues/5) · deep-research 워크플로우 · 2026-07-12
> **라운드 2 재검증(2026-07-13, sonnet 소스 직접 확인)** — YouTube 약관·미국 레시피 저작권 4건 전부 ✅ 확정, 한국 법리 갭필 완료(크롤링 3중 심사기준 + 판례 + 레시피 저작권).
> **용도 주의** — 이 문서는 참고 보관용이다(수요 검증 전 단계). 의사결정에 쓰지 않는다(디자인 문서 Open Q6 규정). 법적 내용은 리서치 요약이지 법률 자문이 아니다.
> 표기 — ✅ 검증됨 / ⚠️ 미검증 / ❌ 기각

## 핵심 결론

1. **업계 표준 과금 구조는 "저장은 무료, AI가 페이월"** — Samsung Food는 URL 레시피 저장 무제한 무료(✅), AI 기능만 유료(✅). 냉파 idea.md의 "사진 분석 월 N회 무료" 설계와 방향이 같다.
2. **사진 분석의 원가는 과금 장벽이 아니다** — 자체 API(Gemini Flash 계열) 기준 호출당 1센트 미만(✅ 가격표), B2B 외주(Passio) 기준으로도 스캔당 $0.05~0.075(✅).
3. **레시피 '재료 목록' 자체는 미국 법리상 저작권 비보호**(⚠️ — 판례·규정 다수 수집, 검증 미완). 냉파의 재료 추출·저장은 저작권 리스크가 낮은 편, 단 조리 설명문 등 표현부를 복제하면 다른 문제.
4. **YouTube 공식 API를 쓸 경우 제약이 실재한다** — 비인증 공개 데이터 30일 저장 제한(✅), 스크래핑 금지·메타데이터 원형 표시·파생 데이터 병합 제한(⚠️). B 단계 설계 시 반드시 재검토.

## 검증된 사실 ✅

### 과금 벤치마크
- Samsung Food+ 구독 — 월 $6.99 / 연 $59.99 (미국 App Store). ([App Store](https://apps.apple.com/us/app/samsung-food-meal-planner/id1133637674))
- AI 기능(개인화 식단, 스마트 커스터마이징)은 Samsung Food+ 유료 전용 (2-1). (동일 출처)
- **웹 URL 레시피 저장은 무료 티어, 횟수 제한 없음** — "Save any recipe from any website and make it your own." (동일 출처)
- Paprika — 앱 내장 브라우저로 임의 웹사이트 레시피를 다운로드·저장하는 기능을 핵심으로 파는 상용 앱이 4개 플랫폼 앱스토어 심사를 통과해 장기 유통 중 — **레시피 추출·저장 상용화의 선례**. ([공식](https://www.paprikaapp.com/))

### API 원가
- Gemini API 무료 티어 존재(2.5 Flash·Flash-Lite 포함), 단 **무료 티어 제출 콘텐츠는 Google 제품 개선에 사용됨** — 사용자 냉장고 사진을 무료 티어로 처리하면 프라이버시 원칙과 충돌. 유료 티어 사용 권장. ([가격](https://ai.google.dev/gemini-api/docs/pricing))
- Gemini 2.5 Flash 입력 $0.30/M(이미지 포함)·출력 $2.50/M, Flash-Lite $0.10/$0.40 — 사진 1장(≈258~1,120토큰) 호출당 입력 원가 1센트 미만. (동일 출처)
- Passio AI(B2B 식품인식 API) Starter $99/월·1M 토큰 포함·초과 $25/M — 사진 1장 20~30k 토큰 ≈ **스캔당 $0.05~0.075**. 외주 시의 원가 기준점. ([가격](https://www.passio.ai/pricing))

### YouTube 약관
- **비인증 공개 데이터(영상 제목 등)는 최대 30일 저장 후 삭제 또는 갱신 의무** (Developer Policies III.E.4.d, 2-0). ([문서](https://developers.google.com/youtube/terms/developer-policies))

## 라운드 2에서 ✅ 확정된 주장 (소스 직접 대조)

### YouTube 약관 상세
- ✅ API 클라이언트의 YouTube 스크래핑 및 스크래핑 데이터 입수 자체 금지(Developer Policies E.6, 검색엔진 예외만 별도) — "must not … directly or indirectly, scrape YouTube Applications … or obtain scraped YouTube data". ([Developer Policies](https://developers.google.com/youtube/terms/developer-policies))
- ✅ **API 데이터와 타 출처 데이터의 병합 금지 + 파생 데이터(예: AI 추출 재료 목록)를 나란히 표시할 땐 구분 명시** — "Merge or combine YouTube API data with any other data." 금지 항목 원문 확인. 냉파 제안 카드 설계에 직접 관련(공식 API 채택 시). ([가이드](https://developers.google.com/youtube/terms/developer-policies-guide))

### 레시피 저작권 (미국)
- ✅ 제7순회 항소법원(Publications Int'l v. Meredith, 88 F.3d 473) — "The identification of ingredients … is a statement of facts", 조리 지시문은 §102(b) 배제. 판결문 원문 확인. ([판결문](https://law.justia.com/cases/federal/appellate-courts/F3/88/473/486900/))
- ✅ USCO Circular 33 — "Recipes consisting only of a listing of ingredients, or a simple set of directions, are not subject to copyright protection." PDF 원문 확인. ([Circ. 33](https://www.copyright.gov/circs/circ33.pdf))
- 단, 실질적 문학적 표현(설명·에세이)이나 요리책 편집물은 보호 가능 — **표현부 복제는 금지선**. (⚠️ FAQ 항목은 라운드 2 미대상) ([copyright.gov FAQ](https://www.copyright.gov/help/faq/faq-protect.html))

## 한국 법리 (라운드 2 갭필 — 신규 정리)

- **크롤링 3중 심사기준** — ①저작권법 데이터베이스제작자 권리(§93) ②정보통신망법 §48①(접근권한) ③부정경쟁방지법 §2①(파)목이 병렬 적용. ([Mondaq](https://www.mondaq.com/copyright/1266554/%EB%8D%B0%EC%9D%B4%ED%84%B0-%ED%81%AC%EB%A1%A4%EB%A7%81%EC%9D%98-%ED%95%9C%EA%B5%AD%EB%B2%95%EC%83%81-%ED%97%88%EC%9A%A9%EA%B8%B0%EC%A4%80))
- **사람인 v. 잡코리아**(서울고법 2016나2019365, 대법 확정) — 창작성 없는 DB도 '상당한 투자'만으로 보호, 반복·체계적 복제 + VPN 우회 접근에 침해 인정. ([법률신문](https://www.lawtimes.co.kr/opinion/117765?serial=117765))
- **야놀자 v. 여기어때**(대법 2021도1533) — 형사 무죄(공개 정보·경미 수집·접근제한 없음)이나 **민사에선 부정경쟁으로 10억 배상** — 형사 무죄와 민사 책임 병존. ([법무법인 세종](https://www.shinkim.com/kor/media/newsletter/1843))
- **4대 실무 판단기준(목적·대상·방법·결과)** — 공개 데이터·아웃링크 방식·비경쟁적 사용은 허용 방향, 미러링·반복 체계적 복제는 위법 방향. (Mondaq)
- **한국 레시피 저작권** — 한국저작권보호원 사례집: "레시피는 일반적으로 아이디어의 영역으로 그 자체는 저작권으로 보호받을 수 없으나 … 레시피북이나 레시피 영상 등 저작물로 표현된 경우에는 그 저작물 자체가 보호" — 미국 법리(아이디어/표현 이분법)와 일치. ([ipdaily 2차 인용](https://www.ipdaily.co.kr/2022/01/15/10/18/20/18487/))
- **B 단계 이월 판단 항목** — 냉파의 수집 방식이 야놀자형(경미·공개·접근제한 없음)인지 사람인형(반복·체계적)인지는 이번 갭필로 판단 불가. 사용자가 URL을 제공하는 MVP 방식은 전자에 가까우나, B 단계에서 자동화 수집을 붙이는 순간 재검토 필수.

## 기각된 주장 ❌

- "Paprika는 freemium이 아니라 플랫폼별 단품 판매다" — 1-2 기각(검증자들이 반박 — 구독 요소 존재 가능성). 과금 모델 인용 시 재확인 필요.

## 냉파에의 시사점 (참고 보관)

- **MVP(질문 검증기)에는 즉각 리스크 없음** — 사용자가 제공한 URL에서 재료 목록(비보호 대상)을 사용자 자신의 레시피 북에 저장하는 구조이고, 공식 YouTube API를 쓰지 않으므로 API 약관의 30일 규정 적용 대상이 아니다. 단 이 해석 자체가 미검증이므로 B 단계 전 법률 확인 항목으로 이월.
- **B 단계 설계 제약 후보** — 공식 API 채택 시: 30일 갱신 잡, 메타데이터 원형 표시, AI 추출 재료의 구분 표시. 지금 아키텍처에 반영하지 말고(YAGNI) 목록만 유지.
- **과금 설계 방향(검증 후)** — "저장 무료 + AI 페이월"이 표준. 원가 구조상 무료 월 N회의 N은 원가가 아니라 전환 심리로 정해도 된다.
- **프라이버시 주의(즉시 적용)** — Gemini 무료 티어는 콘텐츠를 학습에 사용 → 냉장고 사진은 유료 티어로 처리. idea.md의 "사용자 사진 최소수집·격리 원칙"과 직결.

## 출처

전체 목록은 본문 인라인 링크 참조. 주요 primary — Samsung Food App Store · Paprika · Gemini 가격 · Passio 가격 · YouTube Developer Policies/ToS/가이드 · Publications Int'l v. Meredith 판결문 · copyright.gov FAQ/Circ.33 · KCI 논문.
