#!/usr/bin/env bash
# Screenshot the macOS app for the README, as Tools/screenshots.sh does for GNUstep (#75).
#
# Usage: Tools/screenshots_macos.sh [output-dir]          (default: build/screenshots-macos/)
#
# Opens the shared sample (Tools/screenshot-sample/security-settings.png, as the Windows shots use)
# in build/cocoa/ScreenshotTool.app, marks it up, and saves, each as a window with its shadow on a
# transparent background:
#   macos-text.png            the markup, with a label being typed and the text bar showing
#   macos-dark-popover.png    dark mode, the finished markup and the highlighter's settings popover
# A small library (Tools/macos-screenshots/Scenes.m), loaded into the app, sets each scene up.
# The README's macOS images are these, copied to docs/images/.
#
# Build the app first (scripts/build_cocoa.sh). The terminal needs the Screen Recording
# permission (System Settings > Privacy & Security), and the app comes to the front for each shot.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "screenshots_macos: macOS only; use Tools/screenshots.sh elsewhere." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLS="${SCRIPT_DIR}/macos-screenshots"
OUT_DIR="$(mkdir -p "${1:-${ROOT_DIR}/build/screenshots-macos}" && cd "${1:-${ROOT_DIR}/build/screenshots-macos}" && pwd)"
APP="${ROOT_DIR}/build/cocoa/ScreenshotTool.app/Contents/MacOS/ScreenshotTool"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

[[ -x "${APP}" ]] || { echo "screenshots_macos: build the app first (scripts/build_cocoa.sh)" >&2; exit 1; }

clang -dynamiclib -fobjc-arc -framework AppKit "${TOOLS}/Scenes.m" -o "${WORK}/Scenes.dylib"
codesign --force --sign - "${WORK}/Scenes.dylib" >/dev/null 2>&1
swiftc -O "${TOOLS}/capture.swift" -o "${WORK}/capture"
SAMPLE="${ROOT_DIR}/Tools/screenshot-sample/security-settings.png"

# shot <scene> <file> [dark]
shot() {
  local dark=()
  [[ "${3:-}" == dark ]] && dark=(SCREENSHOT_DARK=1)
  env ${dark[@]+"${dark[@]}"} SCREENSHOT_SCENE="$1" DYLD_INSERT_LIBRARIES="${WORK}/Scenes.dylib" \
    SCREENSHOT_TOOL_LOG_PATH="${WORK}/app.log" "${APP}" "${SAMPLE}" >/dev/null 2>&1 &
  local pid=$!
  sleep 1.5
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is ${pid}) to true" \
    >/dev/null 2>&1 || true
  # Long enough for the editing hint to fade.
  sleep 7
  "${WORK}/capture" "${pid}" "${OUT_DIR}/$2"
  kill -KILL "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  echo "screenshots_macos: ${OUT_DIR}/$2"
}

shot text macos-text.png
shot popover macos-dark-popover.png dark
