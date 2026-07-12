# 경쟁 서비스 분석 — fridge-AI·재료매칭 앱의 실패 지점

> wayfinder 티켓 [#2](https://github.com/woosung-dev/cookmark/issues/2) · deep-research 워크플로우 · 2026-07-12
> **라운드 2 재검증(2026-07-13, sonnet 소스 직접 확인)** — 핵심 주장 5건 중 3건 ✅ 확정, 2건 ❌ 기각·정정.
> **라운드 3 리뷰 딥다이브(2026-07-13, opus 완주 — 71 에이전트·오류 0)** — 실사용자 리뷰 원문 기반 12건 확정·3건 기각. 이 문서는 3라운드 통합본이다.

## 핵심 결론 (라운드 2 갱신)

1. **"저장한 출처 레시피 × 냉장고 사진 매칭"을 구현했다고 확인된 앱은 여전히 없다.** 다만 라운드 2에서 정확도가 올라갔다 — Cookiz에 대해 "연결 안 됨"이라고 단정할 근거도 없음이 확인됐다(아래 2번).
2. **정정** — Cookiz는 소셜 임포트 쿡북과 재료 사진 스캔을 한 앱에 모두 가진 최근접 선례라는 점은 유지되지만, "스캔이 저장 쿡북과 매칭되지 않는다"는 단정은 출처에 없는 서술이라 **기각(❌)**됐다. 연결 여부는 미확인 — **실제 설치·사용으로만 판별 가능**하며, 이는 P1 스파이크 전후로 30분짜리 확인 가치가 있다(경쟁 실사용 확인).
3. **정정** — "우리의식탁 리뷰에 개인 레시피 저장·냉장고 재고 추천 기능 요청이 있다"는 주장도 **기각(❌)** — 노출 리뷰에 해당 내용이 없고, '냉장고 재료 기반 AI 추천'은 이미 그 앱의 기존 기능이다. 라운드 1의 "수요 실존 방증" 문장은 철회한다.
4. 이 카테고리의 공통 붕괴 지점 — (a) 수동 입력 마찰 (b) generic AI 레시피 신뢰 부족 (c) 매칭 랭킹의 구조적 왜곡 — 은 라운드 2에서 오히려 **보강**됐다. 만개의레시피 10개 제한은 페이지 소스의 JS 원문으로, Samsung Food 페이월과 Fridge Leftovers AI 서비스 종료는 원문 인용으로 확정.

## 라운드 2 재검증 결과 ✅/❌

- ✅ **만개의레시피 냉장고파먹기 = 텍스트 입력 + 10개 하드 제한** — 페이지 JS 원문 확보: `if ($('#ingredient').val()…split(' ').length > 10) { alert('냉장고 속 재료는 10개 이내로 입력해 주세요.') }`. 이미지 입력 요소 전무.
- ✅ **Fridge Leftovers AI 서비스 종료** — "Fridge Leftovers AI has been sunsetted and is no longer available."
- ✅ **Samsung Food** — "start by making sure your Food List is up to date … This feature is available with our Food+ subscription." 수동 관리 전제 + 유료 잠금 확정. 단 수동 재료 선택 검색(2차 경로)은 구독 제한 언급 없음.
- ❌ **Cookiz 미연결 단정** — 출처에 없음. "Camera or gallery: Cookiz reads what's in the photo and suggests structured recipes"까지만 확인됨.
- ❌ **우리의식탁 리뷰 기능 요청** — 노출 리뷰 4건에 없음. 냉장고 재료 기반 AI 추천은 기존 기능.

## 라운드 3 — 실사용자 리뷰 딥다이브 (opus, 3표 적대적 검증 통과)

냉파의 세 가지 설계 가설이 이번 라운드에서 **실사용자 육성으로** 뒷받침됐다.

### ✅ P3 직접 지지 — "저장 레시피 ↔ 냉장고 매칭"은 미충족 수요다 (high, 3-0)
- AI 계열 앱은 전부 "가진 재료 + AI 생성 아이디어" 방식 — 사용자가 큐레이션한 개인 레시피 라이브러리를 재고와 대조하는 앱은 검증 표본에 없음.
- **Samsung Food 실사용자가 정확히 이 수요를 표현** — 식단 계획 시 저장 레시피 전체를 스크롤해야 하고 "the lack of ability to filter by collection makes the process more time consuming". 이후 업데이트로 일부 개선됐으나 수요 존재 자체의 방증. ([justuseapp](https://justuseapp.com/en/app/1133637674/samsung-food-meal-planner/reviews))

### ✅ "신뢰된 3개" 답 형태 지지 — 추천 반복·generic이 대표 불만 (high, 3-0)
- SuperCook 리뷰 원문(bubblykitten, 2020) — "the app gives me 100 recipes … About 35, maybe 40 of them will be the same recipes … annoying". ([App Store](https://apps.apple.com/us/app/supercook-recipe-by-ingredient/id1477747816?see-all=reviews))
- Ask MetaFilter — 재료매칭 앱들의 추천이 "mostly … pretty tried-and-true 'midwestern' type meals"이고 에스닉 레시피는 "60's Cookbooks" 수준이라는 다양성 실망. 미소된장·한식 재료가 안 먹힌다는 불만 — **한식 특화가 그 자체로 차별화 축**이 될 수 있다는 신호. ([MetaFilter #327455](https://ask.metafilter.com/327455/I-need-Supercook-but-different))

### ✅ 라벨 설계("이것만 사면 가능") 직접 지지 — 정밀 매칭이 핵심 가치 (high, 3-0)
- 실사용자 원문 — "**'You have everything on hand to make Kimbap except pickled radish' is super useful** to me and the remaining shreds of my meal planning skills". 부족 재료 1개를 짚어주는 것이 사용자가 스스로 말하는 킬러 가치 — 냉파 MVP의 제안 라벨 규칙과 정확히 일치. ([MetaFilter #327455](https://ask.metafilter.com/327455/I-need-Supercook-but-different))

### 기타 확정·참고
- Samsung Food — 식이 선호 미반영 불만 + 자동 식단 없음(삼성 공식 FAQ가 자인) (medium, 2-1).
- 냉장고파먹기(집밥) KR 리뷰 — 노출 10건 전부 5★, 불만 0건, **기능 위시만 존재("북마크 기능이 있었으면")** — 북마크 요청은 냉파의 레시피 북과 방향이 같다. 단 App Store 노출 정렬의 우호 편향 주의(표본 부재≠실제 부재) (medium, 2-1).

### ❌ 라운드 3에서 기각된 주장 (근거로 쓰지 말 것)
- "네거티브/다중조건 필터 수요" (1-2), "실시간 재고·기기간 팬트리 동기화 수요" (0-3), "요거트↔사워크림 포장 혼동 오인식 사례" (0-3).

### 한계(caveats)와 열린 질문
- **소스 편중** — 다양성·정밀 매칭 관련 3건이 MetaFilter 단일 스레드(n=1)에서 나옴. "불만이 존재한다"까지만 유효, 광범위성은 미판단.
- **시효성** — 삼성 Bespoke 인식 한계는 CES 2026 Gemini 업그레이드(2,000종 확장)로 완화될 수 있음. 현재 스냅샷으로만 유효.
- 열린 질문 — ① 저장 레시피 매칭 수요의 광범위성(한국 사용자 표본 필요) ② SuperCook 반복 불만이 페이월 탓인지 랭킹 한계인지 ③ Gemini 업그레이드 후 Bespoke 실사용 정확도 ④ 한국 앱 중 이미지 스캔 방식의 한식 재료 인식 실사용 평가.

## 주요 발견 (전부 ⚠️ 미검증)

### 해외 fridge-AI 앱 — photo→generic 생성뿐

- **Fridge AI**(MaGa Srl) — 사진 스캔→자체 생성 레시피. 외부 출처 레시피 매칭 없음. 출시 1년 반에 인도 앱스토어 리뷰 노출 0건 — 트랙션 부재 자체가 신호. ([App Store](https://apps.apple.com/in/app/fridge-ai-food-recipes/id6739216407))
- **Fridge Vision AI** — 사진 최대 5장→AI 생성 레시피, "재료 검출 정확도 95%+" 자사 주장. 출처 레시피 매칭 광고 없음. ([공식](https://fridgevisionai.com/))
- **Fridge Leftovers AI** — **서비스 종료(sunset)**. 카테고리 내 실제 사망 사례. ([공식](https://fridgeleftoversai.com/))
- **Cookiz** — 소셜 임포트 쿡북 + 재료 사진 스캔 동시 보유(최근접 선례). 스캔↔쿡북 연결 여부는 페이지만으로 판별 불가(라운드 2 정정) — 실사용 확인 필요. "신뢰된 소수 제안" 개념은 광고에 없음. ([공식](https://cookiz.app/))

### 국내 incumbents — 사진 인식 자체가 없다

- **만개의레시피 "냉장고 파먹기"** — 재료를 텍스트로 직접 타이핑(띄어쓰기 구분), 입력 **최대 10개 하드 제한**(초과 시 JS alert). 검색 대상은 10만+ 레시피 전체 풀 → 일반 검색 결과 페이지로 이동. 사진 인식·저장 레시피 매칭 없음. ([모바일웹](https://m.10000recipe.com/recipe/ingredients.html), [App Store](https://apps.apple.com/kr/app/%EC%9A%94%EB%A6%AC%EB%B0%B1%EA%B3%BC-%EB%A7%8C%EA%B0%9C%EC%9D%98-%EB%A0%88%EC%8B%9C%ED%94%BC/id494190282))
- **우리의식탁** — 냉장고 재료를 텍스트로 AI에게 요청하는 기능이 이미 존재(사진 인식은 없음). ~~리뷰 기능 요청 주장~~은 라운드 2에서 기각 — 노출 리뷰는 가로모드·레시피 품질·타이머 호평뿐. ([App Store](https://apps.apple.com/kr/app/%EC%9A%B0%EB%A6%AC%EC%9D%98%EC%8B%9D%ED%83%81-%EC%9A%94%EB%A6%AC%EB%A5%BC-%EC%8A%A4%ED%83%80%EC%9D%BC%ED%95%98%EB%8B%A4/id1090371750))
- **냉장고 파먹기(냉파, lazyheroes)** — 재료 수동 선택 + **닫힌 재료 사전**(고등어·통조림·라임 등 부재, 임의 추가 불가)이 반복 불만 1위. 사용자들이 해외 앱의 사진 자동 인식 도입을 직접 요청. 레시피 소스는 개발자 수기 DB. **재료보유율(%) 정렬의 구조적 왜곡**(2/3 > 4/10 — 필요 재료 많은 레시피가 항상 불리)을 사용자가 상세 리뷰로 지적. ([Google Play](https://play.google.com/store/apps/details?id=com.lazyheroes.erfe&hl=en_US))

### Samsung Food(구 Whisk) — incumbent의 한계

- 재료 기반 레시피 검색은 **수동 유지되는 Food List** 전제, 사진·카메라 경로 없음. 핵심 "지금 있는 재료로 뭐 만들지" 기능이 **유료 구독(Food+) 페이월** 뒤. 매칭 대상은 일반 카탈로그(Explore)이지 사용자가 저장한 레시피만이 아님. ([도움말](https://support.samsungfood.com/hc/en-us/articles/30251599415956-How-to-Search-for-Recipes-Using-Your-Available-Ingredients))
- 재료→상품 매칭 실패가 상시 발생함을 공식 문서에서 인정("머신러닝은 지속 훈련 필요") — incumbent도 매칭 신뢰성 미해결. ([FAQ](https://support.samsungfood.com/hc/en-us/articles/360042249292-Button-Integration-FAQs))

### 재고관리 앱 — 입력 정확도 계층에서 붕괴

- **NoWaste** — 보유 재고 기반 AI 레시피 생성 추가됨(출처 레시피 매칭 아님). 반복 불만은 바코드 스캔 정확도(잘못된 유통기한, 수정 불가, 오분류). ([App Store](https://apps.apple.com/us/app/nowaste-food-inventory-list/id926211004))

## 냉파에의 시사점

- **P3(차별화 위치) 지지, 단서 추가** — "내 레시피 북 우선 + 신뢰된 3개"는 조사 범위에서 확인된 구현 사례가 없는 자리다. 단 Cookiz의 연결 여부가 미확인으로 남았으므로, **P1 스파이크 전후에 Cookiz를 직접 설치·사용해 30분 확인**하는 것을 권장한다(유일한 잠재 선점자 판별).
- **랭킹 설계 경고** — 재료보유율 % 정렬의 왜곡(필요 재료 적은 레시피만 상위) 사례는 냉파의 "부족 재료 적은 순 정렬"에도 같은 함정이 있음을 시사. G1 그릴링에서 다룰 것.
- **입력 마찰 = 카테고리의 사인(死因)** — 텍스트 타이핑(만개), 닫힌 사전(냉파앱), 수동 리스트(Samsung Food), 바코드 오류(NoWaste). 사진 1장(P2)의 방향성은 맞고, 관건은 인식 품질(P1 스파이크).

## 출처

primary — [Fridge AI](https://apps.apple.com/in/app/fridge-ai-food-recipes/id6739216407) · [Fridge Vision AI](https://fridgevisionai.com/) · [Fridge Leftovers AI](https://fridgeleftoversai.com/) · [만개의레시피 모바일웹](https://m.10000recipe.com/recipe/ingredients.html) · [만개의레시피 App Store](https://apps.apple.com/kr/app/%EC%9A%94%EB%A6%AC%EB%B0%B1%EA%B3%BC-%EB%A7%8C%EA%B0%9C%EC%9D%98-%EB%A0%88%EC%8B%9C%ED%94%BC/id494190282) · [우리의식탁](https://apps.apple.com/kr/app/%EC%9A%B0%EB%A6%AC%EC%9D%98%EC%8B%9D%ED%83%81-%EC%9A%94%EB%A6%AC%EB%A5%BC-%EC%8A%A4%ED%83%80%EC%9D%BC%ED%95%98%EB%8B%A4/id1090371750) · [냉파(Google Play)](https://play.google.com/store/apps/details?id=com.lazyheroes.erfe&hl=en_US) · [NoWaste](https://apps.apple.com/us/app/nowaste-food-inventory-list/id926211004) · [Samsung Food 도움말 1](https://support.samsungfood.com/hc/en-us/articles/30251599415956-How-to-Search-for-Recipes-Using-Your-Available-Ingredients) · [2](https://support.samsungfood.com/hc/en-us/articles/360042249292-Button-Integration-FAQs) · [Cookiz](https://cookiz.app/) · [Mr.Cook](https://www.mrcook.app/en)
secondary/blog/forum — [Android Authority](https://www.androidauthority.com/samsung-food-3517054/) · [Plan to Eat 리뷰](https://www.plantoeat.com/blog/2026/01/samsung-food-review-pros-and-cons/) · [justuseapp(Whisk)](https://justuseapp.com/en/app/1133637674/whisk-recipes-grocery-list/reviews) · [justuseapp(CozZo)](https://justuseapp.com/en/app/1162606257/cozzo-food-inventory-manager/reviews) · [mealthinker](https://mealthinker.com/blog/samsung-food-alternative) · [recipy 2026 비교](https://recipyapp.com/blog/best-pantry-tracking-apps-2026) · [fango](https://fango.fi/en/blog/best-food-waste-tracker-app/) · [appstory](https://news.appstory.co.kr/battle13974) · [Medium(vibe coder fridge apps)](https://medium.com/@andytlim/every-vibe-coder-eventually-builds-the-scan-your-fridge-app-8827dde02d94)
