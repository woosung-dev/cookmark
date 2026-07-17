# contracts — 계약

API 계약의 **발행 지점**. `openapi.yaml`은 **생성물이지 정본이 아니다** — 정본은 `apps/api`의 Pydantic 모델이다 (ADR-0008 · [ADR-0009](../docs/adr/0009-apps-api-materialization.md)).

## 수기로 수정하지 말 것

`openapi.yaml`을 직접 고치면 다음 재생성이 덮어쓰고, 그 전에 CI가 막는다. **스키마를 바꾸려면 `apps/api`의 코드를 바꾼 뒤 재생성한다.**

```bash
cd apps/api && uv run python scripts/export_openapi.py            # 재생성 (커밋에 포함할 것)
cd apps/api && uv run python scripts/export_openapi.py --check    # 드리프트 검사 (CI가 도는 것과 동일)
```

재생성은 결정적이다 — 같은 코드면 연속 몇 번을 돌려도 같은 파일이다. `.github/workflows/api.yml`의 `계약 스냅샷 (드리프트 = 실패)` 스텝이 매 PR에서 `--check`를 돌려 **어긋나면 머지를 막는다. 자동 커밋은 없다** — 갱신은 사람이 위 명령으로 한다. 같은 워크플로의 `schemathesis` 스텝은 이 발행된 계약을 실 서버에 물려 **구현이 계약을 지키는지**까지 본다.

- **무엇이 들어오는가.** `openapi.yaml`(생성물)뿐이다. **하류 클라이언트 생성기(ts·dart)는 미채택**이라 배선돼 있지 않다 — 트리거는 ADR-0009 계약 절이 쥐고 있고, 채택 전까지 소비자는 수기로 쓴다.
- **어떤 rules가 규율하는가.** **코드 우선 + 커밋된 스냅샷 + CI 드리프트 가드** — `backend.md` §9.2와 ADR-0009 계약 절. 커밋하는 목적은 **스키마 변경이 PR diff로 보이게** 하는 것이다.
- **실체화됨** ([#99](https://github.com/woosung-dev/cookmark/issues/99), 2026-07-17). 선언대로 **`apps/api`의 첫 라우트가 생성물로 낳았다.** 프록시 3개(recognize·extract·match)는 수기 문서화하지 않는다 — [#75](https://github.com/woosung-dev/cookmark/issues/75)가 폐지를 확정한 코드이고 `.mjs` 소스가 승계 입력이자 정본이다.

## 왜 여기 있나 — colocate 관례의 명시적 예외

생성물은 보통 producer 옆에 둔다(`mobile.md` §0.1). `contracts/`는 그 예외다 — **언어·앱을 횡단하는 발행점**이라, 소비자(TS·Dart 클라이언트)가 producer의 내부 경로를 참조하지 않게 한다.

## 정정 이력

**2026-07-17 ([ADR-0009](../docs/adr/0009-apps-api-materialization.md) · [#81](https://github.com/woosung-dev/cookmark/issues/81))** — 이 README의 최초 선언은 *"API 계약 정본 — 클라이언트 생성물·타입의 **상류**"* · *"**계약 우선** — 스키마 변경이 코드 변경에 선행한다"*였다. **역전됐다.** 차팅 시점의 좌표 선언보다 채택된 스택이 이긴다 — FastAPI는 구성상 코드 우선이고, `backend.md` 검증 앵커의 `schemathesis`조차 **생성된 스키마를 읽는다**. "계약 우선"을 고수하면 표준과 첫 적용 사례가 첫날부터 어긋난다.
