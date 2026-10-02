#!/usr/bin/env bash
# Run the ScreenshotTool test suite and capture all output in a single log.
# Fails when any test fails, and also when tests skipped themselves because no
# window server was reachable, so a missing display can't pass for a green run.
# Under CI (no desktop), run it under a virtual display: `xvfb-run -a Tools/run_tests.sh`.
# Build the app first (`make`): the test bundle links the vendored updater libraries.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_PATH="${1:-${ROOT_DIR}/tests.log}"
TEST_HOME="${SCREENSHOT_TOOL_TEST_HOME:-${ROOT_DIR}/.tests_home}"

# A fresh shell (such as a CI step) may not have the GNUstep environment yet.
GNUSTEP_ROOT="${GNUSTEP_ROOT:-/usr/GNUstep}"
if [[ -z "${GNUSTEP_MAKEFILES:-}" && -f "${GNUSTEP_ROOT}/System/Library/Makefiles/GNUstep.sh" ]]; then
  set +u
  # shellcheck disable=SC1091
  . "${GNUSTEP_ROOT}/System/Library/Makefiles/GNUstep.sh"
  set -u
fi

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

for lib in third_party/gnustep-packager-updater/objc/GPUpdaterCore/libGPUpdaterCore.a \
           third_party/gnustep-packager-updater/objc/GPUpdaterUI/libGPUpdaterUI.a; do
  if [[ ! -f "${lib}" ]]; then
    echo "Missing ${lib}: build the app (make) before running the tests." >&2
    exit 1
  fi
done

# Truncate the log before starting the run so Codex can inspect fresh output.
: > "${LOG_PATH}"

# The test runner writes its own output to tests_runner.log in the repository root.
RUNNER_LOG="${ROOT_DIR}/tests_runner.log"
rm -f "${RUNNER_LOG}"

status=0
echo "== ScreenshotTool tests started at $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==" >> "${LOG_PATH}"
"${MAKE:-make}" tests >> "${LOG_PATH}" 2>&1 || status=$?
echo "== ScreenshotTool tests finished at $(date -u +"%Y-%m-%dT%H:%M:%SZ") (exit ${status}) ==" >> "${LOG_PATH}"

if [[ -f "${RUNNER_LOG}" ]]; then
  grep -E "XCTest:|XCTest bundle|Failed to load|not found" "${RUNNER_LOG}" | sed -E 's/^[0-9-]+ [0-9:.]+ [^ ]+ //' || true
fi

if [[ ${status} -ne 0 ]]; then
  echo "Tests failed (exit ${status}). See ${LOG_PATH} and ${RUNNER_LOG}." >&2
  tail -n 20 "${LOG_PATH}" >&2
  exit "${status}"
fi

if grep -q "failed to connect to window server" "${RUNNER_LOG}"; then
  echo "Tests were skipped because no window server was reachable; run under a display (xvfb-run -a)." >&2
  exit 1
fi

if ! grep -qE "[0-9]+ tests PASSED" "${RUNNER_LOG}"; then
  echo "No passing test summary in ${RUNNER_LOG}." >&2
  exit 1
fi

echo "Test suite passed. See ${LOG_PATH} and ${RUNNER_LOG} for details."
