#!/usr/bin/env bash
# Run the ScreenshotTool test suite on macOS with Apple's XCTest.
#
# Builds the test bundle from the app sources and the test files Tests/GNUmakefile lists (the
# same ones Tools/run_tests.sh runs under GNUstep), then runs it with `xcrun xctest`. The tests
# open windows, so run it in a logged-in session (CI runners have one). Needs Xcode, not just the
# Command Line Tools: XCTest comes with Xcode.
#
# Usage: Tools/run_tests_macos.sh [TestClass | TestClass/testMethod ...]
# The log goes to $TEST_LOG (default tests-macos.log).

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This runs the tests with Apple's XCTest; use Tools/run_tests.sh elsewhere." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/cocoa-tests"
OBJ_DIR="${BUILD_DIR}/obj"
BUNDLE="${BUILD_DIR}/ScreenshotToolTests.xctest"
LOG_PATH="${TEST_LOG:-${ROOT_DIR}/tests-macos.log}"
ARCH="$(uname -m)"
FRAMEWORKS="$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks"

if [[ ! -d "${FRAMEWORKS}/XCTest.framework" ]]; then
  echo "XCTest.framework not found under ${FRAMEWORKS}; install Xcode and select it with xcode-select." >&2
  exit 1
fi

# The test files GNUmakefile lists, one per line.
TESTS=()
while IFS= read -r line; do TESTS+=("Tests/${line}"); done < <(
  awk '/^ScreenshotToolTests_OBJC_FILES/ { collecting = 1; next }
       collecting { gsub(/\\/, ""); if ($1 == "") exit; print $1 }' "${ROOT_DIR}/Tests/GNUmakefile")
SOURCES=()
for source in "${ROOT_DIR}"/Source/*.m; do
  [[ "$(basename "${source}")" == "main.m" ]] || SOURCES+=("${source}")
done

rm -rf "${BUNDLE}" "${OBJ_DIR}"
mkdir -p "${OBJ_DIR}" "${BUNDLE}/Contents/MacOS"

CFLAGS=(
  -arch "${ARCH}"
  -fobjc-arc
  -fmodules
  -fmodules-cache-path="${BUILD_DIR}/ModuleCache"
  -g
  -Wall
  -Wno-deprecated-declarations
  -mmacosx-version-min=12.0
  -I"${ROOT_DIR}/Source"
  -I"${ROOT_DIR}/Tests"
  -F"${FRAMEWORKS}"
)

echo "Compiling ${#SOURCES[@]} sources and ${#TESTS[@]} test files..."
for file in "${SOURCES[@]}" "${TESTS[@]/#/${ROOT_DIR}/}"; do
  clang "${CFLAGS[@]}" -c "${file}" -o "${OBJ_DIR}/$(basename "${file}" .m).o"
done

clang -bundle -arch "${ARCH}" -mmacosx-version-min=12.0 "${OBJ_DIR}"/*.o \
  -F"${FRAMEWORKS}" -framework XCTest -framework AppKit \
  -Xlinker -rpath -Xlinker "${FRAMEWORKS}" \
  -o "${BUNDLE}/Contents/MacOS/ScreenshotToolTests"
cat > "${BUNDLE}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ScreenshotToolTests</string>
    <key>CFBundleIdentifier</key>
    <string>com.danboyd.screenshottool.tests</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
</dict>
</plist>
PLIST

FILTER=()
if [[ $# -gt 0 ]]; then
  FILTER=(-XCTest "$(IFS=,; echo "$*")")
fi

# The tests find Resources/ relative to the working directory.
cd "${ROOT_DIR}"
status=0
xcrun xctest "${FILTER[@]+"${FILTER[@]}"}" "${BUNDLE}" > "${LOG_PATH}" 2>&1 || status=$?
grep -E ": error:|Executed [0-9]+ tests" "${LOG_PATH}" | tail -n 40
if [[ "${status}" -ne 0 ]]; then
  echo "Tests failed (exit ${status}); the full log is ${LOG_PATH}." >&2
fi
exit "${status}"
