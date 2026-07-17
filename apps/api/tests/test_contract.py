# 계약 가드 — 커밋된 스냅샷이 코드 정본과 동기인지·재생성이 결정적인지 (외부 행동: 파일 내용·드리프트 판정)
import os
import subprocess
import sys
from pathlib import Path

from scripts.export_openapi import drift, render, write
from tests.conftest import API_ROOT


def _render_in_subprocess(hash_seed: str) -> str:
    """별도 프로세스에서 재생성한다 — PYTHONHASHSEED를 바꿔 set 순회 흔들림을 노출시킨다."""
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            "import sys; from scripts.export_openapi import render; sys.stdout.write(render())",
        ],
        cwd=API_ROOT,
        env={**os.environ, "PYTHONHASHSEED": hash_seed},
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def test_committed_snapshot_is_in_sync() -> None:
    """AC: 스냅샷이 커밋돼 있고 코드 정본과 어긋나지 않는다 (CI 가드의 로컬 동형)."""
    assert drift() is None


def test_drift_detected_when_snapshot_is_stale(tmp_path: Path) -> None:
    """AC 실증의 유닛 동형 — 스키마가 바뀌었는데 스냅샷을 안 갱신하면 잡힌다."""
    stale = tmp_path / "openapi.yaml"
    stale.write_text(render().replace("cookmark-api", "stale-title"), encoding="utf-8")

    report = drift(stale)

    assert report is not None
    # 사람이 읽는 diff — 어긋난 지점이 보여야 재생성 판단이 선다
    assert "stale-title" in report
    assert "cookmark-api" in report


def test_drift_detected_when_snapshot_missing(tmp_path: Path) -> None:
    """스냅샷 부재는 크래시가 아니라 드리프트로 보고된다."""
    assert drift(tmp_path / "absent.yaml") is not None


def test_write_then_check_is_clean(tmp_path: Path) -> None:
    """재생성 직후는 항상 동기 — 가드가 자기 산출물을 통과시킨다."""
    path = tmp_path / "openapi.yaml"

    write(path)

    assert drift(path) is None


def test_regeneration_is_deterministic_across_processes() -> None:
    """AC: 연속 2회 재생성 diff 0. 해시 시드가 달라도 동일해야 한다.

    FastAPI는 `route.methods`(set)를 순회하므로 중간 순서는 프로세스마다 흔들린다 —
    최종 출력이 안정적인 건 Pydantic `PathItem`의 필드 선언 순서가 정규화하기 때문이다.
    그 정규화가 깨지면 가드가 상시 빨간불이 되므로 여기서 못박는다.
    """
    first = _render_in_subprocess("0")
    second = _render_in_subprocess("12345")

    assert first == second
