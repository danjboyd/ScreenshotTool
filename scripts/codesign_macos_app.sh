#!/usr/bin/env bash
# Signs ScreenshotTool.app from the inside out: Sparkle's helpers and framework, then the app.
#
# Usage: scripts/codesign_macos_app.sh <ScreenshotTool.app> [identity]
#   identity   "-" (the default) signs ad hoc; a "Developer ID Application: ..." identity signs
#              for distribution, with the hardened runtime and a secure timestamp.

set -euo pipefail

APP="${1:?usage: codesign_macos_app.sh <ScreenshotTool.app> [identity]}"
IDENTITY="${2:--}"

if [[ "${IDENTITY}" == "-" ]]; then
  FLAGS=(--force --sign - --timestamp=none)
else
  FLAGS=(--force --sign "${IDENTITY}" --options runtime --timestamp)
fi

SPARKLE="${APP}/Contents/Frameworks/Sparkle.framework"
if [[ -d "${SPARKLE}" ]]; then
  # As Sparkle's documentation orders it; the app isn't sandboxed, so it has no XPC services.
  codesign "${FLAGS[@]}" "${SPARKLE}/Versions/B/Autoupdate"
  codesign "${FLAGS[@]}" "${SPARKLE}/Versions/B/Updater.app"
  codesign "${FLAGS[@]}" "${SPARKLE}"
fi
codesign "${FLAGS[@]}" "${APP}"
codesign --verify --strict --deep "${APP}"
