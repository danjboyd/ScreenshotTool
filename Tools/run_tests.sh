#!/usr/bin/env bash
# Run the ScreenshotTool test suite and capture all output in a single log.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_PATH="${1:-${ROOT_DIR}/tests.log}"

# Ensure GNUstep defaults lock directory exists to avoid noisy warnings.
mkdir -p "${HOME}/GNUstep/Defaults/.lck"
mkdir -p "$(dirname "${LOG_PATH}")"

cd "${ROOT_DIR}"

# Truncate the log before starting the run so Codex can inspect fresh output.
: > "${LOG_PATH}"

{
  echo "== ScreenshotTool tests started at $(date -u +"%Y-%m-%dT%H:%M:%SZ") =="
  "${MAKE:-make}" tests
  echo "== ScreenshotTool tests finished at $(date -u +"%Y-%m-%dT%H:%M:%SZ") =="
} >> "${LOG_PATH}" 2>&1

echo "Test suite completed. See ${LOG_PATH} for details."
