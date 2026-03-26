#!/usr/bin/env bash
# Run the ScreenshotTool test suite and capture all output in a single log.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_PATH="${1:-${ROOT_DIR}/tests.log}"
TEST_HOME="${SCREENSHOT_TOOL_TEST_HOME:-${ROOT_DIR}/.tests_home}"

GNUSTEP_SYSTEM_TOOLS=""
GNUSTEP_SYSTEM_LIBRARY=""
if command -v gnustep-config >/dev/null 2>&1; then
  GNUSTEP_SYSTEM_TOOLS="$(gnustep-config --variable=GNUSTEP_SYSTEM_TOOLS 2>/dev/null || true)"
  GNUSTEP_SYSTEM_LIBRARY="$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY 2>/dev/null || true)"
fi

TOOLS_PREFIX="${GNUSTEP_SYSTEM_TOOLS:-/usr/GNUstep/System/Tools}"
LIB_PREFIX="${GNUSTEP_SYSTEM_LIBRARY:-/usr/GNUstep/System/Library}"

# Ensure the GNUstep make tools and libraries are visible before invoking make/tests.
export PATH="${TOOLS_PREFIX}:${PATH}"
export LD_LIBRARY_PATH="${LIB_PREFIX}/Libraries:${LD_LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="${LIB_PREFIX}/Libraries:${DYLD_LIBRARY_PATH:-}"
export HOME="${TEST_HOME}"

# Keep GNUstep defaults isolated inside the repo so tests do not depend on the
# caller's desktop session state or lock permissions.
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
