#!/usr/bin/env bash
# 코어 루프 E2E를 Web 타깃에서 돌린다 — 검증의 정본(코딩 스탠다드)
#
# chromedriver가 없으면: brew install --cask chromedriver
# (Gatekeeper에 걸리면: xattr -d com.apple.quarantine "$(which chromedriver)")
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v chromedriver >/dev/null; then
  echo "chromedriver가 없습니다 — brew install --cask chromedriver" >&2
  exit 1
fi

# 이미 떠 있으면 그대로 쓰고, 아니면 띄우고 끝날 때 정리한다.
if ! curl -sf http://localhost:4444/status >/dev/null 2>&1; then
  chromedriver --port=4444 >/dev/null 2>&1 &
  driver_pid=$!
  trap 'kill "$driver_pid" 2>/dev/null || true' EXIT
  for _ in $(seq 1 20); do
    curl -sf http://localhost:4444/status >/dev/null 2>&1 && break
    sleep 0.5
  done
fi

exec flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/core_loop_test.dart \
  -d web-server \
  --browser-name=chrome \
  --headless \
  "$@"
