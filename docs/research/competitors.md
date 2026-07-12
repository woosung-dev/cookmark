# 경쟁 서비스 분석 — fridge-AI·재료매칭 앱의 실패 지점

> wayfinder 티켓 [#2](https://github.com/woosung-dev/cookmark/issues/2) · deep-research 워크플로우 · 2026-07-12
> **검증 상태 주의** — 실행 중 월 사용량 한도 도달로 3표 적대적 검증이 이 티켓에서는 완료되지 못했다. 아래 주장은 전부 ⚠️ 미검증(소스 수집·추출은 완료, 교차 검증 실패)이다. P1 스파이크·G1 그릴링 진행 근거로는 충분하나, B(정석 SaaS) 진입 결정에 쓰기 전에는 핵심 주장 재검증을 권장한다.

## 핵심 결론

1. **"저장한 출처 레시피 × 냉장고 사진 매칭"을 구현한 앱은 발견되지 않았다.** 조사 범위(해외 fridge-AI 5종, 국내 3종, 재고관리 3종, 레시피 매니저 2종)에서 냉파의 차별화(P3)가 차지하려는 자리는 비어 있다.
2. 가장 근접한 선례는 **Cookiz** — 소셜(유튜브·인스타 등) 레시피 임포트→개인 쿡북과 냉장고 사진 스캔을 **한 앱에 모두** 갖고 있으나, 둘이 연결되어 있지 않다(스캔은 generic AI 레시피 생성으로만 이어짐). 두 프리미티브를 잇는 것이 정확히 냉파의 한 수다.
3. 이 카테고리의 공통 붕괴 지점은 (a) 수동 입력 마찰, (b) generic AI 레시피의 신뢰 부족, (c) 매칭 랭킹의 구조적 왜곡이다 — 전부 냉파 디자인 문서의 프리미스와 정합한다.

## 주요 발견 (전부 ⚠️ 미검증)

### 해외 fridge-AI 앱 — photo→generic 생성뿐

- **Fridge AI**(MaGa Srl) — 사진 스캔→자체 생성 레시피. 외부 출처 레시피 매칭 없음. 출시 1년 반에 인도 앱스토어 리뷰 노출 0건 — 트랙션 부재 자체가 신호. ([App Store](https://apps.apple.com/in/app/fridge-ai-food-recipes/id6739216407))
- **Fridge Vision AI** — 사진 최대 5장→AI 생성 레시피, "재료 검출 정확도 95%+" 자사 주장. 출처 레시피 매칭 광고 없음. ([공식](https://fridgevisionai.com/))
- **Fridge Leftovers AI** — **서비스 종료(sunset)**. 카테고리 내 실제 사망 사례. ([공식](https://fridgeleftoversai.com/))
- **Cookiz** — 소셜 임포트 쿡북 + 냉장고 스캔 동시 보유, 그러나 미연결. "신뢰된 소수 제안" 개념도 없음. ([공식](https://cookiz.app/))

### 국내 incumbents — 사진 인식 자체가 없다

- **만개의레시피 "냉장고 파먹기"** — 재료를 텍스트로 직접 타이핑(띄어쓰기 구분), 입력 **최대 10개 하드 제한**(초과 시 JS alert). 검색 대상은 10만+ 레시피 전체 풀 → 일반 검색 결과 페이지로 이동. 사진 인식·저장 레시피 매칭 없음. ([모바일웹](https://m.10000recipe.com/recipe/ingredients.html), [App Store](https://apps.apple.com/kr/app/%EC%9A%94%EB%A6%AC%EB%B0%B1%EA%B3%BC-%EB%A7%8C%EA%B0%9C%EC%9D%98-%EB%A0%88%EC%8B%9C%ED%94%BC/id494190282))
- **우리의식탁** — 냉장고 재료를 텍스트로 AI에게 요청하는 기능만. 리뷰에서 사용자들이 **'개인 레시피 저장'과 '냉장고 재고 기반 메뉴 추천'을 기능 요청**으로 남기고 있음 — 부재의 방증이자 수요의 실존 근거. ([App Store](https://apps.apple.com/kr/app/%EC%9A%B0%EB%A6%AC%EC%9D%98%EC%8B%9D%ED%83%81-%EC%9A%94%EB%A6%AC%EB%A5%BC-%EC%8A%A4%ED%83%80%EC%9D%BC%ED%95%98%EB%8B%A4/id1090371750))
- **냉장고 파먹기(냉파, lazyheroes)** — 재료 수동 선택 + **닫힌 재료 사전**(고등어·통조림·라임 등 부재, 임의 추가 불가)이 반복 불만 1위. 사용자들이 해외 앱의 사진 자동 인식 도입을 직접 요청. 레시피 소스는 개발자 수기 DB. **재료보유율(%) 정렬의 구조적 왜곡**(2/3 > 4/10 — 필요 재료 많은 레시피가 항상 불리)을 사용자가 상세 리뷰로 지적. ([Google Play](https://play.google.com/store/apps/details?id=com.lazyheroes.erfe&hl=en_US))

### Samsung Food(구 Whisk) — incumbent의 한계

- 재료 기반 레시피 검색은 **수동 유지되는 Food List** 전제, 사진·카메라 경로 없음. 핵심 "지금 있는 재료로 뭐 만들지" 기능이 **유료 구독(Food+) 페이월** 뒤. 매칭 대상은 일반 카탈로그(Explore)이지 사용자가 저장한 레시피만이 아님. ([도움말](https://support.samsungfood.com/hc/en-us/articles/30251599415956-How-to-Search-for-Recipes-Using-Your-Available-Ingredients))
- 재료→상품 매칭 실패가 상시 발생함을 공식 문서에서 인정("머신러닝은 지속 훈련 필요") — incumbent도 매칭 신뢰성 미해결. ([FAQ](https://support.samsungfood.com/hc/en-us/articles/360042249292-Button-Integration-FAQs))

### 재고관리 앱 — 입력 정확도 계층에서 붕괴

- **NoWaste** — 보유 재고 기반 AI 레시피 생성 추가됨(출처 레시피 매칭 아님). 반복 불만은 바코드 스캔 정확도(잘못된 유통기한, 수정 불가, 오분류). ([App Store](https://apps.apple.com/us/app/nowaste-food-inventory-list/id926211004))

## 냉파에의 시사점

- **P3(차별화 위치) 지지** — "내 레시피 북 우선 + 신뢰된 3개"는 조사 범위에서 유일한 빈 자리. 우리의식탁 리뷰의 기능 요청은 이 수요가 실존함을 보여준다.
- **랭킹 설계 경고** — 재료보유율 % 정렬의 왜곡(필요 재료 적은 레시피만 상위) 사례는 냉파의 "부족 재료 적은 순 정렬"에도 같은 함정이 있음을 시사. G1 그릴링에서 다룰 것.
- **입력 마찰 = 카테고리의 사인(死因)** — 텍스트 타이핑(만개), 닫힌 사전(냉파앱), 수동 리스트(Samsung Food), 바코드 오류(NoWaste). 사진 1장(P2)의 방향성은 맞고, 관건은 인식 품질(P1 스파이크).

## 출처

primary — [Fridge AI](https://apps.apple.com/in/app/fridge-ai-food-recipes/id6739216407) · [Fridge Vision AI](https://fridgevisionai.com/) · [Fridge Leftovers AI](https://fridgeleftoversai.com/) · [만개의레시피 모바일웹](https://m.10000recipe.com/recipe/ingredients.html) · [만개의레시피 App Store](https://apps.apple.com/kr/app/%EC%9A%94%EB%A6%AC%EB%B0%B1%EA%B3%BC-%EB%A7%8C%EA%B0%9C%EC%9D%98-%EB%A0%88%EC%8B%9C%ED%94%BC/id494190282) · [우리의식탁](https://apps.apple.com/kr/app/%EC%9A%B0%EB%A6%AC%EC%9D%98%EC%8B%9D%ED%83%81-%EC%9A%94%EB%A6%AC%EB%A5%BC-%EC%8A%A4%ED%83%80%EC%9D%BC%ED%95%98%EB%8B%A4/id1090371750) · [냉파(Google Play)](https://play.google.com/store/apps/details?id=com.lazyheroes.erfe&hl=en_US) · [NoWaste](https://apps.apple.com/us/app/nowaste-food-inventory-list/id926211004) · [Samsung Food 도움말 1](https://support.samsungfood.com/hc/en-us/articles/30251599415956-How-to-Search-for-Recipes-Using-Your-Available-Ingredients) · [2](https://support.samsungfood.com/hc/en-us/articles/360042249292-Button-Integration-FAQs) · [Cookiz](https://cookiz.app/) · [Mr.Cook](https://www.mrcook.app/en)
secondary/blog/forum — [Android Authority](https://www.androidauthority.com/samsung-food-3517054/) · [Plan to Eat 리뷰](https://www.plantoeat.com/blog/2026/01/samsung-food-review-pros-and-cons/) · [justuseapp(Whisk)](https://justuseapp.com/en/app/1133637674/whisk-recipes-grocery-list/reviews) · [justuseapp(CozZo)](https://justuseapp.com/en/app/1162606257/cozzo-food-inventory-manager/reviews) · [mealthinker](https://mealthinker.com/blog/samsung-food-alternative) · [recipy 2026 비교](https://recipyapp.com/blog/best-pantry-tracking-apps-2026) · [fango](https://fango.fi/en/blog/best-food-waste-tracker-app/) · [appstory](https://news.appstory.co.kr/battle13974) · [Medium(vibe coder fridge apps)](https://medium.com/@andytlim/every-vibe-coder-eventually-builds-the-scan-your-fridge-app-8827dde02d94)
