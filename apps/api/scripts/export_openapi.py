# OpenAPI 스냅샷 생성기 — Pydantic 정본에서 contracts/openapi.yaml을 낳는다 (ADR-0009 계약 절 · #99)
import argparse
import difflib
import os
import sys
from pathlib import Path

import yaml

# contracts/는 발행 지점이지 상류가 아니다 — 언어·앱 횡단이라 producer 내부가 아니라 리포 루트에 산다.
# apps/api/scripts/export_openapi.py → parents[3] = 리포 루트.
SNAPSHOT = Path(__file__).resolve().parents[3] / "contracts" / "openapi.yaml"

REGEN_COMMAND = "cd apps/api && uv run python scripts/export_openapi.py"

_HEADER = (
    "# 생성물 — 수기로 수정하지 말 것. 정본은 apps/api의 Pydantic 모델이다 (ADR-0009 계약 절).\n"
    f"# 재생성: {REGEN_COMMAND}\n"
)


def render() -> str:
    """앱의 OpenAPI 스키마를 스냅샷 텍스트로 렌더한다 — 출력은 코드에만 좌우된다(설정 무관)."""
    # main.py가 import 시점에 Settings를 읽는다(CORS·세션 키·IdP 자격증명). 스냅샷은 설정과 무관하므로
    # (허용 origin·세션 키는 미들웨어이지 스키마가 아니다) 미설정 환경에서도 재생성이 1명령이도록
    # 필수 필드를 자리표시자로 채운다 — DB·IdP 연결은 일어나지 않는다. import는 그 뒤여야 해서 함수 안에 둔다.
    for key, placeholder in {
        "DATABASE_URL": "postgresql+asyncpg://contract-export/placeholder",
        "KAKAO_CLIENT_ID": "placeholder",
        "KAKAO_CLIENT_SECRET": "placeholder",
        "GOOGLE_CLIENT_ID": "placeholder",
        "GOOGLE_CLIENT_SECRET": "placeholder",
        "SESSION_SECRET": "placeholder",
        "GEMINI_API_KEY": "placeholder",
    }.items():
        os.environ.setdefault(key, placeholder)
    from src.main import app

    # sort_keys=False — FastAPI가 Pydantic OpenAPI 모델로 직렬화하며 이미 정규 순서를 낳는다.
    # 알파벳 정렬은 openapi→info→paths 자연 순서만 깨서 diff 가독성을 잃는다.
    body: str = yaml.safe_dump(app.openapi(), sort_keys=False, allow_unicode=True)
    return _HEADER + body


def write(path: Path = SNAPSHOT) -> None:
    """스냅샷을 재생성한다."""
    path.write_text(render(), encoding="utf-8")


def drift(path: Path = SNAPSHOT) -> str | None:
    """커밋된 스냅샷과 코드 정본의 차이를 사람이 읽는 diff로 돌려준다. 동기면 None."""
    committed = path.read_text(encoding="utf-8") if path.exists() else ""
    current = render()
    if committed == current:
        return None
    return "".join(
        difflib.unified_diff(
            committed.splitlines(keepends=True),
            current.splitlines(keepends=True),
            fromfile=f"{path.name} (커밋된 스냅샷)",
            tofile="생성 스키마 (코드 정본)",
        )
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="OpenAPI 계약 스냅샷을 재생성하거나 드리프트를 검사한다."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="재생성하지 않고 드리프트만 검사한다 — 어긋나면 1로 종료 (CI 가드 전용, 자동 커밋 없음)",
    )
    args = parser.parse_args(argv)

    if not args.check:
        write()
        print(f"{SNAPSHOT} 갱신")
        return 0

    report = drift()
    if report is None:
        return 0
    sys.stderr.write(report)
    sys.stderr.write(
        f"\n계약 스냅샷이 코드와 어긋났다. 로컬에서 재생성해 커밋할 것.\n  {REGEN_COMMAND}\n"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
