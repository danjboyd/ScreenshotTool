#!/usr/bin/env bash
# Package ScreenshotTool.app into a drag-to-install macOS DMG, optionally signed and notarized.
#
# Usage: scripts/package_macos_dmg.sh [ScreenshotTool.app]
#
# Environment:
#   VERSION              version for the DMG name (default: the app's CFBundleShortVersionString)
#   OUTPUT_DIR           where the DMG goes (default: Staging)
#   DMG_NAME             DMG file name (default: ScreenshotTool-<version>-macOS.dmg)
#   CODESIGN_IDENTITY    a "Developer ID Application: ..." identity; without it the app keeps its
#                        ad hoc signature and the DMG carries a note on opening an unsigned app
#   Notarization, with CODESIGN_IDENTITY (either an App Store Connect API key or an Apple ID):
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#   NOTARIZE_APPLE_ID, NOTARIZE_TEAM_ID, NOTARIZE_PASSWORD

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This packager runs on macOS hosts. Use scripts/package_appimage.sh on Linux." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE="${1:-${ROOT_DIR}/build/cocoa/ScreenshotTool.app}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/Staging}"
STAGING_DIR="${OUTPUT_DIR}/macos-dmg"

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "Missing app bundle at ${APP_BUNDLE}. Build first with scripts/build_cocoa.sh." >&2
  exit 1
fi

if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "${APP_BUNDLE}/Contents/Info.plist")"
fi
VERSION="${VERSION#v}"
DMG_NAME="${DMG_NAME:-ScreenshotTool-${VERSION}-macOS.dmg}"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
ditto "${APP_BUNDLE}" "${STAGING_DIR}/ScreenshotTool.app"
ln -s /Applications "${STAGING_DIR}/Applications"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Signing ScreenshotTool.app with '${CODESIGN_IDENTITY}'"
  codesign --force --options runtime --timestamp --sign "${CODESIGN_IDENTITY}" "${STAGING_DIR}/ScreenshotTool.app"
  codesign --verify --strict --verbose=2 "${STAGING_DIR}/ScreenshotTool.app"
else
  cat > "${STAGING_DIR}/Opening an unsigned app.txt" <<'NOTE'
This build of ScreenshotTool isn't signed by an Apple Developer ID yet, so the first
time you open it macOS says it can't verify the app.

To open it:
1. Drag ScreenshotTool to Applications and double-click it. When macOS warns you,
   click Done.
2. Open System Settings > Privacy & Security, scroll down, and click "Open Anyway"
   next to the message about ScreenshotTool. Confirm with your password.

Or, in Terminal:
    xattr -dr com.apple.quarantine /Applications/ScreenshotTool.app

You only need to do this once per download.
NOTE
fi

mkdir -p "${OUTPUT_DIR}"
rm -f "${DMG_PATH}"
echo "Creating ${DMG_PATH}..."
hdiutil create -volname "ScreenshotTool ${VERSION}" -srcfolder "${STAGING_DIR}" -ov -format ULFO "${DMG_PATH}"
rm -rf "${STAGING_DIR}"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "${CODESIGN_IDENTITY}" "${DMG_PATH}"

  notary_auth=()
  if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    notary_auth=(--key "${NOTARY_KEY_PATH}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER_ID}")
  elif [[ -n "${NOTARIZE_APPLE_ID:-}" && -n "${NOTARIZE_TEAM_ID:-}" && -n "${NOTARIZE_PASSWORD:-}" ]]; then
    notary_auth=(--apple-id "${NOTARIZE_APPLE_ID}" --team-id "${NOTARIZE_TEAM_ID}" --password "${NOTARIZE_PASSWORD}")
  fi
  if [[ ${#notary_auth[@]} -gt 0 ]]; then
    echo "Submitting the DMG for notarization..."
    xcrun notarytool submit "${DMG_PATH}" "${notary_auth[@]}" --wait
    xcrun stapler staple "${DMG_PATH}"
  else
    echo "No notarization credentials; the DMG is signed but not notarized." >&2
  fi
fi

(cd "${OUTPUT_DIR}" && shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256")
echo "DMG ready: ${DMG_PATH}"
cat "${DMG_PATH}.sha256"
