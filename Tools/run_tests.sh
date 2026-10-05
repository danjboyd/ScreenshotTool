#!/usr/bin/env bash
# Run the ScreenshotTool test suite and capture all output in a single log.
# Fails when any test fails, and also when tests skipped themselves because no
# window server was reachable, so a missing display can't pass for a green run.
# Under CI (no desktop), run it under a virtual display: `xvfb-run -a Tools/run_tests.sh`.
# Build the app first (`make`): the test bundle links the vendored updater libraries.
#
# Usage: Tools/run_tests.sh [TestClass | TestClass/testMethod | -xctest-option ...]
#   Tools/run_tests.sh                               the whole suite
#   Tools/run_tests.sh FitViewportRoundingProbeTests one class (or Class/testMethod)
#   Tools/run_tests.sh -test-iterations 20 ...       any xctest option, passed through
# The log goes to $TEST_LOG (default tests.log) and JUnit XML to $TEST_JUNIT (default tests-junit.xml).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_PATH="${TEST_LOG:-${ROOT_DIR}/tests.log}"
JUNIT_PATH="${TEST_JUNIT:-${ROOT_DIR}/tests-junit.xml}"

# Bare names select tests; options (and the values of those that take one) go to xctest as they are.
XCTEST_OPTIONS=()
takes_value=""
for arg in "$@"; do
  if [[ -n "${takes_value}" ]]; then
    XCTEST_OPTIONS+=("${arg}")
    takes_value=""
  elif [[ "${arg}" == -* ]]; then
    XCTEST_OPTIONS+=("${arg}")
    case "${arg}" in
      -test-iterations|-junit-report|-output-format|-host|-host-launch-timeout|-performance-baselines) takes_value=1 ;;
    esac
  else
    XCTEST_OPTIONS+=("-only-testing:ScreenshotToolTests/${arg}")
  fi
done
XCTEST_OPTIONS+=(-junit-report "${JUNIT_PATH}")
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

rm -f "${JUNIT_PATH}"
printf -v XCTEST_ARGS '%q ' "${XCTEST_OPTIONS[@]}"

status=0
echo "== ScreenshotTool tests started at $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==" >> "${LOG_PATH}"
"${MAKE:-make}" tests XCTEST_ARGS="${XCTEST_ARGS}" >> "${LOG_PATH}" 2>&1 || status=$?
echo "== ScreenshotTool tests finished at $(date -u +"%Y-%m-%dT%H:%M:%SZ") (exit ${status}) ==" >> "${LOG_PATH}"

# Per-class results, failures and the summary; filtered-out classes are left out.
grep -E "XCTest:" "${LOG_PATH}" | grep -vE "^[^X]*XCTest:   [A-Za-z]+Tests SKIPPED$" | sed -E 's/^[0-9-]+ [0-9:.]+ [^ ]+ //' \
  | grep -E "tests (PASSED|FAILED)|FAILED|skipped|Skipped|SKIPPED|Assertion|error" || true

if [[ ${status} -ne 0 ]]; then
  echo "Tests failed (exit ${status}). See ${LOG_PATH} and ${JUNIT_PATH}." >&2
  tail -n 20 "${LOG_PATH}" >&2
  exit "${status}"
fi

# Tests skip themselves (XCTSkipIf) without a window server; that must not pass for green.
if grep -q "failed to connect to window server" "${LOG_PATH}"; then
  echo "Tests were skipped because no window server was reachable; run under a display (xvfb-run -a)." >&2
  exit 1
fi

if ! grep -qE "[0-9]+ tests PASSED" "${LOG_PATH}"; then
  echo "No passing test summary in ${LOG_PATH}." >&2
  exit 1
fi

echo "Test suite passed. See ${LOG_PATH} and ${JUNIT_PATH} for details."
