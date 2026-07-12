# 기술 검증 — 사진→재료 인식 모델·정확도·원가

> wayfinder 티켓 [#3](https://github.com/woosung-dev/cookmark/issues/3) · deep-research 워크플로우 · 2026-07-12
> **라운드 2 재검증(2026-07-13, sonnet 소스 직접 확인)** — 원가·토큰 주장 4건 ✅ 확정(1건은 프레이밍 정정), 영상 토큰 수치 1건 ❌ 정정. 보완 스윕에서 인식 실패 모드 신규 수집(⚠️).
> 표기 — ✅ 검증됨 / ⚠️ 미검증 / ❌ 기각

## 핵심 결론

1. **음식·재료 인식에서 Gemini 계열이 벤치마크 최상위**라는 것은 검증된 사실이다(✅ 2건). 모델 1순위 후보는 Gemini Flash 계열 — 성능·원가·지연 모두에서 유리.
2. **다중 품목 이미지에서 정확도가 크게 떨어진다**(✅) — 냉장고 사진은 정확히 이 최악 조건이다. P2 킬 기준(사진당 수동 수정 5개)의 현실성은 문헌으로 결론 낼 수 없고, **P1 스파이크(실물 사진)가 반드시 필요**하다.
3. 사진 1장당 원가는 어느 모델이든 **1센트 미만~수 센트** 수준(✅ 라운드 2 확정)이라 원가가 MVP의 병목이 될 가능성은 낮다. **프레이밍 정정** — JFB 실측치는 이미지당 4회 호출 기준의 '호출당' 값이라 이미지 1장당은 약 4배(Gemini 2.5 Flash ≈ $0.006/장). 그래도 결론은 동일하다.
4. 유튜브 재료 추출은 **설명란 파싱 → 자막(yt-dlp) → 영상 이해** 순으로 시도하는 게 비용 구조상 합리적이다. **수치 정정(라운드 2)** — 영상 입력은 263이 아니라 기본 해상도 **초당 약 300토큰**(프레임 258 + 오디오 32), 저해상도는 초당 약 100토큰. 10분 영상 ≈ 18만 토큰(기본) 또는 6만 토큰(저해상도) — "영상 직접 처리가 가장 비싸다"는 방향성은 유지.

## 검증된 사실 ✅

- **FoodNExTDB 6모델 벤치마크** — Gemini(2.0 Flash)가 Expert-Weighted Recall 평균 70.16%로 최고. ChatGPT(GPT-4o) 64.32%, Claude 3.5 Sonnet 65.86%. ([arXiv 2504.06925](https://arxiv.org/html/2504.06925v1))
- **다중 품목 급락** — 같은 벤치마크에서 Gemini 카테고리 레벨 EWR이 단일 품목 94.52% → 다중 품목 82.18%로 하락. 냉장고 사진(수십 품목 겹침)에 직결되는 조건. ([arXiv 2504.06925](https://arxiv.org/html/2504.06925v1))
- **DiningBench 세밀 분류** — Gemini 3 Flash Preview 81.83%, Gemini 3 Pro 81.55% vs GPT-4o 65.26%, Claude Sonnet 4.5 54.40%. 음식 도메인에서 Gemini 우위의 2차 정량 근거. ([arXiv 2604.10425](https://arxiv.org/html/2604.10425))
- **bag-of-features 한계** — 비전 LLM은 지배적 구성 요소만 식별하고 썰기 방식·질감 같은 미세 차이는 구분 못함 — "손질된 재료" 인식의 구조적 한계. ([arXiv 2604.10425](https://arxiv.org/html/2604.10425))
- **JFB 벤치마크** — 범용 VLM 중 GPT-4o가 최고(Overall 74.1, Ingredient F1 0.737). Gemini가 항상 이기는 건 아니라는 균형 근거. ([arXiv 2508.09966](https://arxiv.org/html/2508.09966v1))

## 라운드 2 재검증 결과 (원가·토큰)

- ✅ JFB 실측(2025-08, Table 2 원문 일치) — **호출당** Gemini 2.5 Flash $0.0014/13.5초, GPT-4o $0.0065/10.3초, Gemini 2.5 Pro $0.0225/28.1초. 단 'Best' 구성은 이미지당 4회 호출 → **이미지 1장당 Flash ≈ $0.006**. ([arXiv 2508.09966](https://arxiv.org/html/2508.09966v1))
- ✅ Gemini 공식 가격(원문 일치) — 2.5 Flash 입력 $0.30/M(텍스트·이미지·비디오)·출력 $2.50/M, 2.5 Flash-Lite $0.10/$0.40. ([가격](https://ai.google.dev/gemini-api/docs/pricing))
- ✅ 이미지 토큰 산정(원문 일치) — 양변 384px 이하 258토큰, 초과 시 768×768 타일당 258토큰 → 냉장고 사진 1장 원가는 결정적으로 계산 가능. ([문서](https://ai.google.dev/gemini-api/docs/image-understanding))
- ❌→정정 — "영상 263토큰/초"는 원문에 없는 수치. 실제는 기본 해상도 초당 약 300토큰(프레임 258+오디오 32), 저해상도 초당 약 100토큰. ([문서](https://ai.google.dev/gemini-api/docs/tokens))
- ✅ 냉장고 인식 실패 모드(원문 일치) — "occlusions, variable distortions, and complex backgrounds … require frontal and close-up images". ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC11652515/))

## 보완 스윕 신규 수집 ⚠️ (2026-07-13, 인식 실패 모드 — 검증 미완)

- 냉동칸은 성에·유사 용기·적층 때문에 특히 인식이 어렵다. 시야에서 가려진 품목은 false negative를 만든다. 조명·반사·각도가 정확도에 유의미하게 영향. ([fitham.ai](https://fitham.ai/en/blog/ai-fridge-scanner/))
- 유사 포장 오인(플레인 요거트 vs 사워크림), 냉장고 내부 LED 색온도·밝기 편차, 소형 품목의 저픽셀 문제(1080p+ 필요), 시간 경과에 따른 식품 외관 변화(변색·시듦)가 정적 이미지 모델을 흔든다. ([basic.ai](https://www.basic.ai/blog-post/computer-vision-for-smart-fridges-how-it-works-models-data-and-annotations))
- 공개 음식 데이터셋(Food-101 등)은 냉장고 특유 조건이 없어 프로덕션급 인식에는 부족 — 업체들은 자체 데이터셋을 구축한다. (동일 출처)
- 전용 모델 참고치 — BroadFPN-YOLACT는 60~100cm 소형 물체 95.0% mAP(표준 YOLACT 72.3%). ([Frontiers](https://www.frontiersin.org/journals/artificial-intelligence/articles/10.3389/frai.2024.1442948/full))

## 미검증 주장 ⚠️ (라운드 1 잔여)

### 원가·지연
- Claude Haiku 4.5 $1/$5, Sonnet 5 $2/$10(2026-08-31까지 프로모션). OpenAI는 gpt-5.4-nano $0.20/$1.25부터. ([Claude 가격](https://platform.claude.com/docs/en/about-claude/pricing) · [OpenAI 가격](https://developers.openai.com/api/docs/pricing))
- Gemini 2.5 Flash-Lite TTFT 0.35초 — 측정 대상 중 2위로 낮음. ([Artificial Analysis](https://artificialanalysis.ai/models))

### 실패 모드·난이도
- 식품 특화 모델(FoodLMM)조차 VIREO Food-172 재료 인식 F1 68.97 — 재료 인식은 특화 모델도 F1 70 미만인 난제. ([arXiv 2312.14991](https://arxiv.org/html/2312.14991v1))
- 전용 CNN 냉장고 시스템은 "내부 1장 사진"을 회피하고 출입 순간 개별 촬영 방식을 씀 — 1장 시나리오의 난이도 방증. ([Frontiers](https://www.frontiersin.org/journals/artificial-intelligence/articles/10.3389/frai.2024.1442948/full))
- 단일 2D 사진에선 양 추정 불가, 숨은 재료(기름·설탕) 인식 불가. ([arXiv 2511.08215](https://arxiv.org/html/2511.08215))

## 기각된 주장 ❌

- "조리 스타일 식별은 최고 모델도 ~50% EWR에 그쳐 조리된 반찬 인식이 훨씬 어렵다" — 검증 1-2로 기각. 수치 해석 이의 가능성. 반찬 인식 난이도 자체는 P1 스파이크에서 실측할 것.

## 냉파에의 시사점

- **모델 선택** — 1순위 Gemini Flash 계열(2.5 Flash 또는 3 Flash Preview). 디자인 문서의 "Gemini Vision 1개" 결정과 정합. 원가는 병목 아님.
- **P1 스파이크 설계 입력** — 다중 품목 급락(✅)과 가림·용기 실패 모드(⚠️) 때문에, 스파이크는 "정돈된 냉장고"가 아니라 **실제 상태(겹침·반찬통 포함)** 사진으로 해야 의미가 있다. 수동 수정 개수를 세는 것이 곧 P2 킬 기준 실측.
- **유튜브 재료 추출 전략** — ①설명란 파싱(무료) → ②자막 yt-dlp(무료) → ③영상 이해(고비용)의 폴백 체인. MVP의 "추출 실패 시 수동 입력 폴백"과 결합하면 충분.

## 출처

[arXiv 2504.06925(FoodNExTDB)](https://arxiv.org/html/2504.06925v1) · [arXiv 2604.10425(DiningBench)](https://arxiv.org/html/2604.10425) · [arXiv 2508.09966(JFB)](https://arxiv.org/html/2508.09966v1) · [arXiv 2312.14991(FoodLMM)](https://arxiv.org/html/2312.14991v1) · [arXiv 2511.08215](https://arxiv.org/html/2511.08215) · [arXiv 2406.16469](https://arxiv.org/pdf/2406.16469) · [arXiv 2509.07400](https://arxiv.org/abs/2509.07400) · [PMC11652515](https://pmc.ncbi.nlm.nih.gov/articles/PMC11652515/) · [Frontiers AI](https://www.frontiersin.org/journals/artificial-intelligence/articles/10.3389/frai.2024.1442948/full) · [Gemini 가격](https://ai.google.dev/gemini-api/docs/pricing) · [이미지 이해](https://ai.google.dev/gemini-api/docs/image-understanding) · [토큰](https://ai.google.dev/gemini-api/docs/tokens) · [영상 이해](https://ai.google.dev/gemini-api/docs/video-understanding) · [Claude 가격](https://platform.claude.com/docs/en/about-claude/pricing) · [OpenAI 가격](https://developers.openai.com/api/docs/pricing) · [Artificial Analysis](https://artificialanalysis.ai/models) · [AI Hub 한국 음식 데이터셋](https://aihub.or.kr/aihubdata/data/view.do?dataSetSn=79) · [yt-dlp 자막 블로그](https://skipthewatch.com/blog/yt-dlp-youtube-subtitles) · [YouTube→레시피 블로그](https://angel-baez.com/blog/youtube-to-recipe-with-ai/)
