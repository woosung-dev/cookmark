# 브랜드 UI = Apple식 절제 구조 + 홍시(감) 퍼시먼 액센트

MVP UI의 시각 언어를 **Apple식 절제된 구조**(라이트 쿨 뉴트럴 그룹 리스트·단일 액센트·희소한 그림자·타이트 타이포) 위에 **홍시(감) 퍼시먼 액센트**(브랜드 필 `#E8552D` / 액션 `#C0391B`)를 얹는 것으로 확정한다. 온기·식욕·먹는 즐거움은 뉴트럴이 아니라 **액센트에만** 둔다. 다출처 리서치(웹 색채심리·오방색·맥락0 독립 에이전트 5·ui-ux-pro-max 색DB·taste-skill/MengTo 규율)와 소크라테스식 논증으로 도출했다. 상세 스펙은 루트 `DESIGN.md`, 도출 과정은 `docs/design/color-decision.md`.

## Considered Options

- **구조 후보** — MengTo(에디토리얼 럭셔리)·ui-ux-pro-max+design-html(사용성)·다중 브랜드 DESIGN.md(Apple·Linear·Notion·Airbnb) 및 하이브리드까지 device-scale 앱으로 제작해 4모델·2 taste 스킬로 평가. **Apple/Airbnb가 최소 AI-slop**으로 수렴 → Apple 구조 채택. 냉파 커스텀(웜 크림+테라코타+세리프)은 taste-skill §4.2가 "premium-consumer AI-tell"로 지목해 기각.
- **색상 후보(1차)** — 감·고추장 레드 `#D2452E`가 식욕·집밥·AA(4.53)로 1위였으나, 브랜드 가치에 "**먹는 즐거움(joy/delight)**"이 추가되며 재평가.
- **감·고추장 레드 유지** — 식욕·집밥엔 강하나 진지·강렬(passion/urgency)해 "즐거움"은 약함. 2위로 강등.
- **나물 그린 `#2E7D50`** — 낭비방지·신선·차별화엔 강하나 집밥 온기·즐거움 언더슛(반복 평가에서 "차갑다·헬스앱"). 리드 기각, "바로 가능/신선" **시맨틱**으로 채택.

## Consequences

- **홍시(감) 퍼시먼이 최종 액센트.** 곶감(말린 감) = "버릴 것 없이(냉파) 인내로 더 달게(즐거움)" — 낭비방지 ∩ 즐거움을 한 색에 담는 브랜드 은유. hue ~13°로 배달앱 오렌지(21°)보다 redder라 차별화. 무편향 즐거움 에이전트 2개가 독립적으로 감/persimmon에 수렴.
- **접근성 2단 구조 필수** — vivid `#E8552D`는 대비 3.6이라 흰 텍스트 금지(필·그래픽 전용), 버튼 등 흰 텍스트 컨트롤은 `#C0391B`(AA 5.47). 뉴트럴은 쿨 클린(`#F5F5F7/#FFF/#1D1D1F`), 크림/베이지 금지.
- **세리프 디스플레이 배제** — taste-skill "세리프 디폴트=AI tell" + Apple 관용과 상충. 위계는 크기·굵기·색으로.
- **DESIGN.md 규약 채택** — Google Stitch 규약대로 루트 `DESIGN.md`(에이전트 read). 파일럿은 Flutter Web이므로 토큰을 Flutter ThemeData/색상으로 매핑해 구현. 색상 변경 시 DESIGN.md를 단일 소스로 갱신.
- 프로토타입 탐색물(30+ 산출)은 `design-explorations/`(미커밋 스크래치)에 두고, keeper(스크린샷·근거·보고서)만 `docs/design/exploration/`에 아카이브.
