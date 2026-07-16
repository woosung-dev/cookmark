# 체크리스트 — #53 (applied-app.jpeg 제안 라벨 배지에 §7 아이콘 추가)

브랜치 `design/53-badge-icon` · 베이스 = main · 트랙 = 디자인/실행(wayfinder 맵 밖).

정본 — 디자인 언어 = `DESIGN.md` §2·§7·§8("색+아이콘 이중 신호") · 아이콘 매핑 = 코드 `lib/ui/widgets/suggestion_card.dart:12` `_styleOf`.
대상은 **목업 1장뿐**이다. 코드·`DESIGN.md`는 이미 정본과 일치 — 손대지 않는다. 선행 = #32(PR #52, 색 재렌더).

---

## 0. 조사

- [x] 이월 근거 확인 — #32 checklist "범위 밖"·context-notes 이월 절에서 아이콘을 별도 이슈로 분리한 사유 확인
- [x] 코드 정본 대조 — `_styleOf`: ready=`check_circle_outline`(0xe15a) · buyOne=`add_shopping_cart`(0xe05a) · maybe=`swap_horiz`(0xe625). `_LabelBadge`: `Icon(size:14)` + `SizedBox(Space.xs=4)` + text
- [x] 대상 배지 인벤토리(3개) — ④ ready·④ buyOne·⑤ ready. maybe는 목업에 카드 0건, danger는 라벨이 아니라 부족재료 칩(아이콘 없음)
- [x] 목업 배지 실측 — pill 외곽·텍스트 좌우단·이웃 clearance·열 정렬

## 1. 아이콘 합성

- [x] 아이콘 소스 = `MaterialIcons-Regular.otf`(앱 번들 폰트) 0xe15a·0xe05a, 14px, fg색 렌더 → 알파 추출
- [x] ④ "바로 가능"(ready) — 좌측 18.5px 확장(우단 고정, 텍스트 보존) + check_circle_outline
- [x] ⑤ "바로 가능"(ready) — 동일
- [x] ④ "이것만 사면 가능"(buyOne) — 우측 18px 확장(좌단=열 정렬 고정, 텍스트 +18) + add_shopping_cart, "부족·굴소스" danger 칩 +18 이동(간격 보존)
- [x] 재인코딩 — 원본 양자화 테이블 + 크로마 4:4:4(#32와 동일)

## 2. 검증

- [x] 코드 렌더 대조(체크박스 ②) — 아이콘을 코드와 **동일 폰트·동일 codepoint**에서 추출(구성상 동일 글리프). size 14·배치(아이콘→gap→텍스트)도 코드에서 직접. gap=5px(코드 Space.xs=4를 목업 스케일 ~1.4×에 비례 환산)
- [x] 색 회귀 = 0 — 평탄대 스포이드로 bg가 #32 목표 유지: go/buy maxΔ=3, danger Δ≤1(JPEG 양자화 바닥). fg·아이콘색 = 토큰 무변경
- [x] 대비 WCAG AA — 아이콘 fg는 텍스트와 동일 색 → #32 실측 그대로: go 5.57:1 · buy 5.23:1 · danger 5.00:1
- [x] 변경 범위 — 배지 3영역(+이동한 danger 칩) 밖은 재인코딩 노이즈만(채널평균 0.029/255, p98=1, max=17 음식사진 고주파)
- [x] 육안 — ④·⑤ 전체 문맥 + 배지 확대 전후 대조

## 3. 문서

- [x] `docs/design/README.md` — "⚠️ 남은 갭 하나 … 아이콘이 목업 배지엔 없다" → 해소(#53) 반영
- [x] 컨텍스트 노트 — 방법·실측 좌표·성장 방향 결정·기각안·스크립트 미커밋 사유 기록

## 4. 마감

- [ ] 커밋
- [ ] `/code-review` — 양 축
- [ ] PR 발행 (`Closes #53`)
- [ ] 머지 → 이슈 #53 닫힘

---

## 범위 밖 (의도적)

- **④ "부족 · 굴소스" 칩** — 제안 라벨이 아니라 **부족 재료 칩**이다. 코드 `_MissingChips`는 아이콘을 그리지 않는다 → 아이콘 없음. (#53에서는 buyOne 확장에 밀려 +18px 위치만 이동, 스타일 무변경.)
- **"애매하지만 가능"(maybe / `swap_horiz`)** — 목업 6화면에 이 라벨 카드가 없다(합성 대상 0건).
- **레이아웃 미정합** — 목업은 배지를 메뉴명 옆/아래에 두고 코드는 카드 상단 Row에 둔다. #53은 **아이콘만** 추가하고 위치 구조는 #32처럼 그대로 둔다.
- **코드·`DESIGN.md`** — 이미 정본(아이콘 포함). 무변경.
