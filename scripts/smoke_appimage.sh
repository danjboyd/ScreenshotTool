#!/usr/bin/env bash
# Smoke-launch a packaged AppImage long enough to confirm it starts and opens
# a sample image. Intended for Linux CI and local packaging validation.

set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This smoke test runs on Linux hosts." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APPIMAGE_PATH="${1:-${ROOT_DIR}/Staging/ScreenshotTool-x86_64.AppImage}"
IMAGE_PATH="${2:-${ROOT_DIR}/Resources/ScreenshotToolIcon.png}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-8}"
LOG_PATH="${SCREENSHOT_TOOL_LOG_PATH:-/tmp/screenshottool-appimage-smoke.log}"

if [[ ! -x "${APPIMAGE_PATH}" ]]; then
  echo "AppImage missing or not executable: ${APPIMAGE_PATH}" >&2
  exit 1
fi

if [[ ! -f "${IMAGE_PATH}" ]]; then
  echo "Smoke-test image missing: ${IMAGE_PATH}" >&2
  exit 1
fi

rm -f "${LOG_PATH}"

# Capture the real exit status: inside `if ! cmd; then`, $? is always 0, which hid crashes.
status=0
timeout "${TIMEOUT_SECONDS}s" env \
    APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}" \
    SCREENSHOT_TOOL_LOG_PATH="${LOG_PATH}" \
    "${APPIMAGE_PATH}" "${IMAGE_PATH}" || status=$?

if [[ "${status}" -ne 0 && "${status}" -ne 124 ]]; then
  echo "AppImage failed to launch cleanly (exit ${status})." >&2
  exit "${status}"
fi

if ! grep -q "openImageAtURL loaded" "${LOG_PATH}"; then
  echo "Smoke launch did not open the sample image. Recent log output:" >&2
  tail -n 40 "${LOG_PATH}" >&2 || true
  exit 1
fi

echo "AppImage smoke test passed: ${APPIMAGE_PATH}"
