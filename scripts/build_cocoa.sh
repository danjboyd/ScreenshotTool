#!/usr/bin/env bash
# Build a Cocoa-native ScreenshotTool.app without GNUstep dependencies.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script builds the macOS Cocoa target; run it on macOS." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/cocoa"
OBJ_DIR="${BUILD_DIR}/obj"
APP_DIR="${BUILD_DIR}/ScreenshotTool.app"
APP_MACOS="${APP_DIR}/Contents/MacOS"
APP_RESOURCES="${APP_DIR}/Contents/Resources}"

mkdir -p "${OBJ_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_MACOS}"
mkdir -p "${APP_DIR}/Contents/Resources"

CFLAGS=(
  -fobjc-arc
  -fmodules
  -fobjc-link-runtime
  -fobjc-weak
  -ObjC
  -Wall -Wextra
  -Wno-deprecated-declarations
  -mmacosx-version-min=11.0
  -ISource
)
LDFLAGS=(
  -mmacosx-version-min=11.0
  -framework AppKit
  -framework Foundation
  -framework CoreGraphics
  -framework CoreText
)

SOURCES=(
  Source/main.m
  Source/AppDelegate.m
  Source/ScreenshotCanvasView.m
  Source/MarkupStroke.m
  Source/MarkupText.m
  Source/STFloatingPopover.m
  Source/STFloatingPopoverWindow.m
  Source/STFloatingPopoverBackgroundView.m
  Source/STHyperlinkButton.m
  Source/ScreenshotToolSettings.m
  Source/ToolSettingsPopoverController.m
  Source/TextToolPopoverController.m
  Source/PreferencesWindowController.m
  Source/STThemeUtilities.m
)

echo "Compiling ${#SOURCES[@]} Objective-C files..."
for src in "${SOURCES[@]}"; do
  base="$(basename "${src}" .m)"
  clang "${CFLAGS[@]}" -c "${ROOT_DIR}/${src}" -o "${OBJ_DIR}/${base}.o"
done

echo "Linking app executable..."
clang "${OBJ_DIR}"/*.o "${LDFLAGS[@]}" -o "${APP_MACOS}/ScreenshotTool"
chmod +x "${APP_MACOS}/ScreenshotTool"

echo "Copying resources..."
rsync -a "${ROOT_DIR}/Resources/" "${APP_DIR}/Contents/Resources/"
cp "${ROOT_DIR}/Resources/Info-cocoa.plist" "${APP_DIR}/Contents/Info.plist"

echo "Cocoa build complete: ${APP_DIR}"
echo "Run it with: ${APP_DIR}/Contents/MacOS/ScreenshotTool"
