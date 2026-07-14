---
# 냉파(cookmark) 디자인 시스템 — 에이전트가 읽는 단일 소스. Google Stitch DESIGN.md 규약.
version: 1
name: cookmark-design-system
description: >
  냉파(cookmark)의 UI 디자인 언어. Apple식 절제된 구조(라이트 쿨 뉴트럴 그룹 리스트·단일 액센트·희소한 그림자)
  위에, 브랜드 온기·식욕·먹는 즐거움을 담는 '홍시(감) 퍼시먼' 액센트를 얹는다. 온기는 뉴트럴이 아니라 액센트에만 둔다.
  참조: 코어 스펙은 CONTEXT.md, 결정 근거는 docs/adr/0006, 색상 도출은 docs/design/color-decision.md.
platform: 모바일 앱(Flutter Web 파일럿, iOS 관용 준수). 랜딩 아님.
dials:  # 1-10
  variance: 3   # Apple 절제 — 대칭·정돈. 랜딩식 비대칭 아님.
  motion: 3     # 미묘·기능적. 시네마틱 아님.
  density: 5    # 앱 밀도(휑하지도 번잡하지도 않게).

colors:
  # 브랜드 액센트 (단일, 절제)
  brand:            "#E8552D"   # 홍시(감) 퍼시먼 — 로고·히어로·일러스트·큰 필. vivid. 흰 텍스트 금지(대비 3.6)
  action:           "#C0391B"   # 곶감브릭 — 버튼·활성·핵심 어포던스(흰 텍스트). AA 5.47
  action-pressed:   "#9A2E15"   # 눌림·hover. AA 7.6
  action-tint:      "#FBE7E2"   # 선택·아주 옅은 배경
  on-action:        "#FFFFFF"
  # 뉴트럴 (쿨 클린 — 크림 금지)
  bg:               "#F5F5F7"   # 앱 배경(iOS grouped)
  surface:          "#FFFFFF"   # 카드·시트·리스트
  text:             "#1D1D1F"   # 본문·제목(순수 검정 아님)
  muted:            "#6E6E73"   # 보조·캡션
  hairline:         "#D2D2D7"   # 1px 구분선
  sunken:           "#EDEDF0"   # 입력·스켈레톤
  # 시맨틱(색+아이콘 이중 신호)
  go-fg:            "#1F6B43"   go-bg:  "#E4F1E9"   # 바로 가능 = 나물 그린(신선·성공)
  buy-fg:           "#8A5A12"   buy-bg: "#FBF0DA"   # 이것만 사면 가능 = 앰버
  maybe-fg:         "#5B5B60"   maybe-bg:"#EFEFF2"  # 애매하지만 가능 = 그레이
  danger:           "#B23A25"   danger-bg:"#FBE7E2" # 부족 재료·에러

typography:
  sans:    "'SF Pro Display','SF Pro Text','Pretendard','IBM Plex Sans KR',system-ui,sans-serif"
  mono:    "'IBM Plex Mono',ui-monospace,monospace"
  large-title: { size: 30, weight: 700, tracking: -0.4 }   # px. 화면 대제목
  title:       { size: 20, weight: 600, tracking: -0.3 }   # 네비바 타이틀
  headline:    { size: 17, weight: 600 }
  body:        { size: 16, weight: 400, line: 1.5 }
  subhead:     { size: 15, weight: 400 }
  footnote:    { size: 13, weight: 400 }
  caption:     { size: 12, weight: 500 }
  numeric:     { family: mono, feature: tabular }          # 매칭률·23/30·수량

spacing:  { base: 4, scale: [4,8,12,16,20,24,32], screen-pad: 16, row-min: 52, touch-min: 44 }
rounded:  { chip: 8, control: 12, card: 16, pill: 9999, photo: 12 }
elevation:
  flat:   "none"                              # 네비바·탭바·리스트·카드 기본
  photo:  "0 6px 20px rgba(29,29,31,.10)"     # 음식 사진이 표면 위에 놓일 때만(단일-그림자 철학)
  sheet:  "0 -8px 30px rgba(29,29,31,.12)"    # 바텀시트
---

# 냉파(cookmark) 디자인 시스템

## 1. Overview — 브랜드 personality & 감정 톤
냉파는 "냉장고를 파먹자(있는 재료로 해먹기·낭비 방지)"에서 출발해 "**요리·먹는 즐거움을 더한다**"로 확장된 제품이다. 그래서 톤은 **따뜻함 · 집밥 · 신뢰 · 그리고 즐거움(delight)**.
구조는 Apple식으로 **절제·정돈·신뢰**를 담고(라이트 쿨 뉴트럴 그룹 리스트, 단일 액센트, 희소한 그림자), 온기·식욕·즐거움은 **홍시(감) 퍼시먼 액센트**가 담당한다. 곶감(말린 감)처럼 "있는 것을 인내로 더 달게" — 낭비 방지와 즐거움을 하나로 은유하는 색이다. 밀도는 앱 밀도(density 5), 변주·모션은 낮게(3/3) — 마케팅 랜딩의 시네마틱·비대칭은 배제.

## 2. Colors — 시맨틱 역할 & 사용 규칙
- **홍시 퍼시먼 브랜드** `#E8552D` — 로고·히어로·큰 필·일러스트. vivid, 즐거움. **흰 텍스트를 얹지 말 것**(대비 3.6, AA 미달).
- **곶감브릭 액션** `#C0391B` — 버튼·활성 탭·체크·핵심 어포던스(흰 텍스트, AA 5.47). pressed `#9A2E15`.
- **뉴트럴(쿨 클린)** — bg `#F5F5F7` / surface `#FFFFFF` / text `#1D1D1F`(순수 검정 아님) / muted `#6E6E73` / hairline `#D2D2D7`. **온기는 뉴트럴이 아니라 액센트에만.** 크림/베이지 배경 금지.
- **시맨틱(제안 라벨, 색+아이콘 이중 신호)** — 바로 가능=나물 그린 `#1F6B43`/`#E4F1E9` · 이것만 사면 가능=앰버 `#8A5A12`/`#FBF0DA` · 애매하지만 가능=그레이 `#5B5B60`/`#EFEFF2` · 부족 재료=딥레드 `#B23A25`.
- **단일 액센트 잠금**: 액션색은 페이지 전체에서 하나. 섹션마다 다른 색 금지.

## 3. Typography
- **본문·UI·제목**: SF Pro / Pretendard / IBM Plex Sans KR. 제목은 타이트 네거티브 트래킹(-0.3~-0.4px), 위계는 크기·굵기·색으로.
- **수치**: IBM Plex Mono(tabular) — 매칭률·23/30·수량·타이머.
- **금지**: 세리프 디스플레이(taste-skill "세리프 디폴트=AI tell", Apple 관용과 상충). Inter를 디폴트로 쓰지 않음.

## 4. Layout & Spacing
- iOS **그룹/인셋 리스트**. 4/8 스페이싱 스케일(4·8·12·16·20·24·32). 화면 좌우 여백 16.
- 리스트 행 ≥52px, 터치 타깃 ≥44px. 상단 네비바 + 하단 **탭바**(메인 ↔ 레시피 북, 아이콘+라벨, 활성 하이라이트).
- 앱 밀도 유지 — 마케팅용 큰 여백·40px+ 히어로 타이포 금지. 좌우 스크롤 금지.

## 5. Elevation & Depth (Apple 단일-그림자 철학)
- 깊이는 **표면 색 대비(bg↔surface) + 1px hairline**으로. 카드·버튼·바는 기본 flat(그림자 없음).
- 그림자는 **음식 사진**이 표면 위에 놓일 때만 `0 6px 20px rgba(29,29,31,.10)`. 바텀시트만 `0 -8px 30px rgba(29,29,31,.12)`.

## 6. Shapes (라운드)
칩/배지 8 · 버튼/입력/셀 12 · 카드/시트/미디어 16 · 제안 라벨·토글 pill · 음식 썸네일 12. **한 라운드 스케일로 잠금**.

## 7. Components
- **버튼(primary)**: action 배경 + 흰 텍스트, radius 12, 그림자 없음, active `scale(0.98)`. 화면당 1개. **secondary**: surface + 1px hairline.
- **탭바**: frosted(backdrop-blur) 하단, 아이콘+라벨, 활성 action 하이라이트.
- **리스트 셀**: 좌 썸네일(photo)/아이콘 + 제목(headline)+보조(footnote muted) + 우 chevron/액션. 1px hairline.
- **제안 카드**: surface, radius 16, photo 그림자. 음식 사진(4:3/1:1) + 요리명 + 출처 뱃지 + 제안 라벨(색+아이콘) + 부족 재료 칩 + 매칭률(mono) + "영상 보기"(secondary)·"이거 했어요"(primary).
- **confidence 체크박스**: 정사각. high=채워진 체크(action) / medium=체크+"확인" 앰버 배지 / low=빈 체크 dim.
- **제안 상세**: 바텀시트(16:9 히어로 + 있는/부족 재료 + 제휴 담기 + 영상 이어보기 + 이거 했어요).
- **로딩**: 레이아웃 모양의 스켈레톤 시머(원형 스피너 지양). **빈/에러 상태**도 구성.
- 아이콘: 일관된 SVG 세트, 스트로크 통일. 이모지 아이콘 금지.

## 8. Do's & Don'ts
**Do**
- 온기·식욕·즐거움은 **홍시/곶감 액센트**에만. 뉴트럴은 쿨 클린 유지.
- 액션 버튼은 `#C0391B`(AA), vivid `#E8552D`는 필/그래픽 전용(흰 텍스트 금지).
- 제안 라벨은 색+아이콘 이중 신호. 수치는 mono tabular. 실제 음식 사진 사용.
- 터치 ≥44px, 본문 ≥16px, 대비 WCAG AA.

**Don't**
- 웜 크림/베이지 배경 + 브라스/클레이 액센트 + 에스프레소 텍스트(AI-slop 디폴트) 금지.
- 세리프 디스플레이·Inter 디폴트·순수 검정(#000)·AI-퍼플/네온·그라데이션 장식 금지.
- 다중 액센트·제네릭 회색 카드+드롭섀도 남발·이모지 아이콘·마케팅 히어로 타이포 금지.
- 배달앱 오렌지(#EA580C) 지양 — 우리는 더 redder한 홍시(감).
