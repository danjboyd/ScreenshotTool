#!/usr/bin/env bash
# Package ScreenshotTool.app into a macOS DMG (optional codesign/notarize).

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This packager runs on macOS hosts. Use scripts/package_appimage.sh on Linux." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE="${1:-${ROOT_DIR}/ScreenshotTool.app}"
STAGING_DIR="${ROOT_DIR}/Staging/macos"
DMG_NAME="${DMG_NAME:-ScreenshotTool-macOS.dmg}"
DMG_PATH="${ROOT_DIR}/Staging/${DMG_NAME}"

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "Missing app bundle at ${APP_BUNDLE}. Build first (scripts/build_macos.sh)." >&2
  exit 1
fi

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
rsync -a --delete "${APP_BUNDLE}/" "${STAGING_DIR}/ScreenshotTool.app/"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Codesigning ScreenshotTool.app with identity '${CODESIGN_IDENTITY}'"
  codesign --force --deep --options runtime --sign "${CODESIGN_IDENTITY}" "${STAGING_DIR}/ScreenshotTool.app"
fi

rm -f "${DMG_PATH}"
echo "Creating DMG at ${DMG_PATH}..."
hdiutil create -volname "ScreenshotTool" -srcfolder "${STAGING_DIR}/ScreenshotTool.app" -ov -format UDZO "${DMG_PATH}"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Verifying signature..."
  codesign --verify --deep --strict --verbose=2 "${DMG_PATH}"
fi

if [[ -n "${NOTARIZE_APPLE_ID:-}" && -n "${NOTARIZE_TEAM_ID:-}" && -n "${NOTARIZE_PASSWORD:-}" ]]; then
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "${DMG_PATH}" --apple-id "${NOTARIZE_APPLE_ID}" --team-id "${NOTARIZE_TEAM_ID}" --password "${NOTARIZE_PASSWORD}" --wait
  xcrun stapler staple "${DMG_PATH}"
fi

echo "DMG ready: ${DMG_PATH}"
shasum -a 256 "${DMG_PATH}"
