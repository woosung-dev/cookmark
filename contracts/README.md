# contracts — 계약

이 디렉토리는 비어 있다. 코드가 아니라 좌표다 (ADR-0008 · [ADR-0009](../docs/adr/0009-apps-api-materialization.md)).

- **무엇이 들어오는가.** API 계약의 **발행 지점** — `openapi.yaml`(생성물). **정본이 아니다.** 정본은 `apps/api`의 Pydantic 모델이다.
- **어떤 rules가 규율하는가.** **코드 우선 + 커밋된 스냅샷 + CI 드리프트 가드.** 스키마는 코드에서 생성되며, 커밋하는 목적은 **스키마 변경이 PR diff로 보이게** 하는 것이다. 가드는 CI 전용 차단(재생성 → diff 있으면 PR 차단)이고 **자동 커밋은 없다** — 갱신은 사람이 로컬 재생성 명령으로 한다. 하류 클라이언트는 생성물이며 수기 수정 금지.
- **실체화 트리거.** **`apps/api`의 첫 라우트가 생성물로 낳는다.** 프록시 3개(recognize·extract·match)는 수기 문서화하지 않는다 — [#75](https://github.com/woosung-dev/cookmark/issues/75)가 폐지를 확정한 코드이고 `.mjs` 소스가 승계 입력이자 정본이다.

## 왜 여기 있나 — colocate 관례의 명시적 예외

생성물은 보통 producer 옆에 둔다(`mobile.md` §0.1). `contracts/`는 그 예외다 — **언어·앱을 횡단하는 발행점**이라, 소비자(TS·Dart 클라이언트)가 producer의 내부 경로를 참조하지 않게 한다.

## 정정 이력

**2026-07-17 ([ADR-0009](../docs/adr/0009-apps-api-materialization.md) · [#81](https://github.com/woosung-dev/cookmark/issues/81))** — 이 README의 최초 선언은 *"API 계약 정본 — 클라이언트 생성물·타입의 **상류**"* · *"**계약 우선** — 스키마 변경이 코드 변경에 선행한다"*였다. **역전됐다.** 차팅 시점의 좌표 선언보다 채택된 스택이 이긴다 — FastAPI는 구성상 코드 우선이고, `backend.md` 검증 앵커의 `schemathesis`조차 **생성된 스키마를 읽는다**. "계약 우선"을 고수하면 표준과 첫 적용 사례가 첫날부터 어긋난다.
