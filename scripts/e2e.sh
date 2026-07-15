#!/usr/bin/env bash
# E2E(검증의 정본) 실행 — chromedriver를 띄우고 Web 타깃으로 integration_test를 돌린다.
# 사용법: scripts/e2e.sh [--headed]
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v chromedriver > /dev/null; then
  echo "chromedriver가 없습니다. 설치: npx @puppeteer/browsers install chromedriver@stable" >&2
  exit 1
fi

# Chrome과 chromedriver의 메이저 버전이 어긋나면 세션 생성이 실패한다 — 먼저 알려준다.
echo "chromedriver: $(chromedriver --version | awk '{print $2}')"

PORT=4444
chromedriver --port=$PORT > /tmp/cookmark-chromedriver.log 2>&1 &
CHROMEDRIVER_PID=$!
trap 'kill $CHROMEDRIVER_PID 2> /dev/null || true' EXIT

# chromedriver가 포트를 열 때까지 기다린다.
for _ in $(seq 1 20); do
  nc -z localhost $PORT 2> /dev/null && break
  sleep 0.2
done

DEVICE_ARGS=(-d web-server --browser-name=chrome --headless)
if [[ "${1:-}" == "--headed" ]]; then
  DEVICE_ARGS=(-d chrome)
fi

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/core_loop_test.dart \
  "${DEVICE_ARGS[@]}"
