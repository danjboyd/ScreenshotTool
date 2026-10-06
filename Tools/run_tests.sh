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
# TEST_THEME=Adwaita runs the suite with that GNUstep theme (default: GNUstep's own); the theme must
# be installed, or in $TEST_LIBRARY_DIR/Themes (a GNUstep Library folder used instead of the user's).
#
# Each test class runs in its own xctest process, one at a time, so a crash fails only that class
# and a class's leftovers (a theme it switched to, say) can't reach the next. Each test has
# $TEST_TIME_ALLOWANCE seconds (default 60) before it fails, so a hang can't stall the run.
# TEST_ISOLATION=0 runs every class in one process instead (quicker to start; for debugging).

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
      -test-iterations|-junit-report|-output-format|-host|-host-launch-timeout|-performance-baselines|\
      -parallel-testing-enabled|-parallel-testing-worker-count|-test-timeouts-enabled|\
      -default-test-execution-time-allowance|-maximum-test-execution-time-allowance|\
      -test-execution-order|-test-execution-order-seed|-attachments-path) takes_value=1 ;;
    esac
  else
    XCTEST_OPTIONS+=("-only-testing:ScreenshotToolTests/${arg}")
  fi
done
XCTEST_OPTIONS+=(-junit-report "${JUNIT_PATH}")
if [[ "${TEST_ISOLATION:-1}" != 0 ]]; then
  # One worker: the classes share one display, so they must not run at the same time.
  XCTEST_OPTIONS+=(-parallel-testing-enabled YES -parallel-testing-worker-count 1)
fi
XCTEST_OPTIONS+=(-default-test-execution-time-allowance "${TEST_TIME_ALLOWANCE:-60}")
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

# GNUstep ignores HOME for its defaults and reads the user's real ones (theme included). A private
# GNUstep.conf points the defaults at the test home instead, so the tests run with GNUstep's own
# theme, as in CI, and never write to the user's settings. GNUstep ignores a config file that's
# writable by anyone but its owner.
SYSTEM_GNUSTEP_CONF="${GNUSTEP_CONFIG_FILE:-/etc/GNUstep/GNUstep.conf}"
TEST_GNUSTEP_CONF="${TEST_HOME}/GNUstep.conf"
mkdir -p "${TEST_HOME}"
{
  [[ -f "${SYSTEM_GNUSTEP_CONF}" ]] && grep -vE '^(GNUSTEP_USER_DEFAULTS_DIR|GNUSTEP_USER_CONFIG_FILE|GNUSTEP_USER_DIR_LIBRARY)=' "${SYSTEM_GNUSTEP_CONF}"
  echo "GNUSTEP_USER_DEFAULTS_DIR=${TEST_HOME}/GNUstep/Defaults"
  echo "GNUSTEP_USER_CONFIG_FILE=${TEST_HOME}/.GNUstep.conf.unused"
  [[ -n "${TEST_LIBRARY_DIR:-}" ]] && echo "GNUSTEP_USER_DIR_LIBRARY=${TEST_LIBRARY_DIR}"
} > "${TEST_GNUSTEP_CONF}"
chmod 600 "${TEST_GNUSTEP_CONF}"
export GNUSTEP_CONFIG_FILE="${TEST_GNUSTEP_CONF}"

# Each run starts with empty test defaults, so a setting a test left behind (a theme, say) can't
# carry into the next run. Then the theme for this run, set in the test defaults' global domain,
# or none (GNUstep's own) (#74).
rm -rf "${TEST_HOME:?}/GNUstep/Defaults"
mkdir -p "${TEST_HOME}/GNUstep/Defaults"
export ST_EXPECT_THEME="${TEST_THEME:-}"
if [[ -n "${TEST_THEME:-}" ]]; then
  printf '{\n  GSTheme = "%s";\n}\n' "${TEST_THEME}" > "${TEST_HOME}/GNUstep/Defaults/NSGlobalDomain.plist"
else
  rm -f "${TEST_HOME}/GNUstep/Defaults/NSGlobalDomain.plist"
fi

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
