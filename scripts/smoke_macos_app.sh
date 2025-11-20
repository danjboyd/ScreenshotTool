#!/usr/bin/env bash
# Lightweight macOS launch smoke: start the app, wait briefly, and kill it.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Smoke test is for macOS only." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE="${1:-${ROOT_DIR}/ScreenshotTool.app}"
LOG_PATH="${LOG_PATH:-${ROOT_DIR}/screenshottool-smoke.log}"
TIMEOUT="${TIMEOUT:-5}"

if [[ ! -x "${APP_BUNDLE}/Contents/MacOS/ScreenshotTool" ]]; then
  echo "Binary missing: ${APP_BUNDLE}/Contents/MacOS/ScreenshotTool" >&2
  exit 1
fi

: > "${LOG_PATH}"

echo "Launching ScreenshotTool.app headlessly for ${TIMEOUT}s (log: ${LOG_PATH})"
SCREENSHOT_TOOL_LOG_PATH="${LOG_PATH}" "${APP_BUNDLE}/Contents/MacOS/ScreenshotTool" >/dev/null 2>&1 &
APP_PID=$!

sleep "${TIMEOUT}"
if ps -p "${APP_PID}" >/dev/null 2>&1; then
  kill "${APP_PID}" >/dev/null 2>&1 || true
fi

echo "Smoke complete. Inspect ${LOG_PATH} for startup traces."
