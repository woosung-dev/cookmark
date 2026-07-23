# #145 체크리스트 — ADR-0011 + 리포 문서 정합 (ADR-0005 역전 기록)

티켓 정본은 [#145](https://github.com/woosung-dev/cookmark/issues/145), 상류는 스펙 [#140](https://github.com/woosung-dev/cookmark/issues/140)(지도 [#129](https://github.com/woosung-dev/cookmark/issues/129) · 게이트 GO [#134](https://github.com/woosung-dev/cookmark/issues/134) · posture [#133](https://github.com/woosung-dev/cookmark/issues/133) · 계측 [#136](https://github.com/woosung-dev/cookmark/issues/136) · 서명 [#132](https://github.com/woosung-dev/cookmark/issues/132)). 결정 로그는 context-notes.md.

목표 한 줄 — **리포 문서가 현재 상태(네이티브 APK 파일럿)를 말한다. 새 세션 에이전트가 `AGENTS.md`를 읽고 "우선 타깃 = Web"으로 오작동하지 않고, 미래 독자가 ADR-0005만 보고 "웹 배포가 맞다"고 오판하지 않는다.**

범위 경계 — 이 티켓은 **리포 트리 문서**(ADR·`AGENTS.md`·`coding-standards.md`·`CONTEXT.md`)만. GitHub 이슈 문서(#41 절차·#65 체크리스트·#9 규약)는 **#146**의 몫이다.

## 산출물

- [x] 작업 문서(checklist·context-notes) — #145로 갱신
- [x] **ADR-0011 신규** — `docs/adr/0011-native-android-pilot-target.md`. 배포 타깃을 웹→네이티브 APK로 역전. 계보(2026-07-19 그릴링·파운더 3× 최공격)·기각 대안·결과(즉시배포 상실+#133·계측 #136·웹 폐기 시퀀싱·서명 연속성 #132) 담김. Flutter 단일 코드베이스는 **유지**(역전 대상=배포 타깃, 스택 아님)
- [x] **ADR-0005 역전 포인터** — 배포 타깃 부분이 ADR-0011로 대체됨을 명시. 서술 자체는 지우지 않음(#31 재서명 관례). 최상단 배너 + 영향 줄 인라인 중첩 주석
- [x] **`AGENTS.md`** — "우선 타깃 = Web 빌드" 서술·로컬 실행 명령·E2E 타깃을 네이티브 현재 상태로 갱신. 섹션 헤더도 ADR-0011 가리킴
- [x] **`docs/coding-standards.md`** — 스택·영속층(SharedPreferences·서명 연속성)·테스트 타깃(Web 타깃 E2E 잔여)의 웹 전제 갱신
- [x] **`CONTEXT.md`** — 주간 백업 글로서리 "인앱 브라우저 유실 보험" 근거를 네이티브 기준으로 조정. 백업 자체·가구 합산 수집 지점 역할은 불변
- [x] **웹이 왜 아직 살아 있는지** 문서가 말한다 — ADR-0011 웹 폐기 시퀀싱 + AGENTS·coding-standards 포인터. 남은 웹 코드를 결함으로 오해하지 않게
- [x] **`README.md`** (AC 밖·goal 정합) — "Web 빌드가 우선 타깃" 한 줄이 티켓 goal 정면 위배라 2줄 수정. context-notes 결정 5

## 검증

- [x] 도메인 용어 `CONTEXT.md` 글로서리 준수(`_Avoid_` 표류 없음)
- [x] 문서 간 상호 링크 정합(ADR-0005↔0011 양방향, AGENTS·coding-standards·README가 ADR-0011 가리킴)
- [x] `flutter analyze` — No issues found(코드 무손상 확인)
- [x] §5 종결 콜론 스캔 — none
- [ ] `/code-review` — Standards·Spec 두 축
- [ ] 커밋
