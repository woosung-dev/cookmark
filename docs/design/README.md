<!-- 냉파 디자인 문서 인덱스 — 무엇이 어디에 있는지 -->
# 냉파(cookmark) 디자인 문서

역할 분리(누가 읽는가):
- **`/DESIGN.md`** (루트) — **에이전트가 읽는 살아있는 디자인 스펙**. Google Stitch 규약(YAML 토큰 + 8섹션). 색·타입·간격·컴포넌트·Do/Don't의 단일 소스. UI를 만들거나 바꿀 땐 이 파일을 먼저·항상 갱신.
- **`docs/adr/0006-brand-color-and-app-shell.md`** — **결정 스냅샷**. Apple 구조 + 홍시 퍼시먼을 왜 골랐는지, 무엇을 기각했는지.
- **`docs/design/color-decision.md`** — **색상 도출 보고서**(사람용). 3가치·다출처 리서치·소크라테스 논증·순위.
- **`docs/design/applied-app.jpeg`** — **적용 화면 목업**(Apple 구조 + 홍시 퍼시먼, 6화면). 제안 라벨 배지는 `DESIGN.md` §2 시맨틱 토큰으로 재렌더됨(#32 — 그린/앰버/딥레드, 결정 #29). §2·§8의 "색+아이콘 이중 신호" 중 **아이콘도 추가됨**(#53 — ready=`check_circle_outline`·buyOne=`add_shopping_cart`, 코드 `_styleOf`와 동일 글리프). 색·아이콘 모두 정본과 일치.

## 핵심 결론 (요약)
- **구조**: Apple식 절제(라이트 쿨 뉴트럴 그룹 리스트·단일 액센트·희소 그림자·타이트 타이포).
- **브랜드 색**: **홍시(감) 퍼시먼** — 브랜드/필 `#E8552D`, 액션(버튼) `#C0391B`(AA), pressed `#9A2E15`. 온기는 액센트에만.
- **시맨틱**: 바로 가능=나물 그린 · 이것만 사면=앰버 · 애매=그레이 · 부족=딥레드.
- **은유**: 곶감 = "버릴 것 없이(냉파) 인내로 더 달게(즐거움)" — 낭비방지 ∩ 즐거움.

## 구현 시 (Flutter Web)
`DESIGN.md`의 토큰을 Flutter `ThemeData`/`ColorScheme`로 매핑. 액션색=primary(`#C0391B`), 브랜드 vivid=강조 필, 뉴트럴=surface/background, 시맨틱 3색=제안 라벨. 색 변경은 `DESIGN.md` → 코드 순.
