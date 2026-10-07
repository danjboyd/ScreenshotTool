#!/usr/bin/env bash
# Smoke-launch ScreenshotTool.app long enough to confirm it starts and opens a sample image, as
# scripts/smoke_appimage.sh does for the AppImage.
#
# Usage: scripts/smoke_macos_app.sh [ScreenshotTool.app] [image]

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Smoke test is for macOS only." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE="${1:-${ROOT_DIR}/build/cocoa/ScreenshotTool.app}"
IMAGE_PATH="${2:-${ROOT_DIR}/Resources/ScreenshotToolIcon.png}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-8}"
LOG_PATH="${SCREENSHOT_TOOL_LOG_PATH:-${TMPDIR:-/tmp}/screenshottool-macos-smoke.log}"
BINARY="${APP_BUNDLE}/Contents/MacOS/ScreenshotTool"

if [[ ! -x "${BINARY}" ]]; then
  echo "Binary missing: ${BINARY}" >&2
  exit 1
fi
if [[ ! -f "${IMAGE_PATH}" ]]; then
  echo "Smoke-test image missing: ${IMAGE_PATH}" >&2
  exit 1
fi

rm -f "${LOG_PATH}"

echo "Launching ${APP_BUNDLE} for ${TIMEOUT_SECONDS}s (log: ${LOG_PATH})"
SCREENSHOT_TOOL_LOG_PATH="${LOG_PATH}" "${BINARY}" "${IMAGE_PATH}" >/dev/null 2>&1 &
APP_PID=$!

sleep "${TIMEOUT_SECONDS}"
if ! kill -0 "${APP_PID}" 2>/dev/null; then
  status=0
  wait "${APP_PID}" || status=$?
  echo "ScreenshotTool exited during the smoke launch (exit ${status}). Recent log output:" >&2
  tail -n 40 "${LOG_PATH}" >&2 || true
  exit 1
fi
kill "${APP_PID}" 2>/dev/null || true
wait "${APP_PID}" 2>/dev/null || true

if ! grep -q "openImageAtURL loaded" "${LOG_PATH}"; then
  echo "Smoke launch did not open the sample image. Recent log output:" >&2
  tail -n 40 "${LOG_PATH}" >&2 || true
  exit 1
fi

echo "macOS smoke test passed: ${APP_BUNDLE}"
