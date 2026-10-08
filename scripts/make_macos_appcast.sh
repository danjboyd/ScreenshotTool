#!/usr/bin/env bash
# Writes the Sparkle update feed (appcast) for one macOS release: the DMG's download URL, its
# EdDSA signature and length, and its version. The release job publishes it to Pages as
# updates/macos/<channel>.xml, which the app's SUFeedURL names.
#
# Usage: scripts/make_macos_appcast.sh <app> <dmg> <download-url> <release-page-url> <out.xml>
#   <app>   the ScreenshotTool.app in the DMG, for its version and build number
#
# The private key comes from $SPARKLE_ED_PRIVATE_KEY (as in CI), or else from the keychain account
# $SPARKLE_KEY_ACCOUNT (default ScreenshotTool), where Sparkle's generate_keys keeps it.

set -euo pipefail

APP="${1:?usage: make_macos_appcast.sh <app> <dmg> <download-url> <release-page-url> <out.xml>}"
DMG="${2:?}"
URL="${3:?}"
PAGE="${4:?}"
OUT="${5:?}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGN_UPDATE="$("${SCRIPT_DIR}/fetch_sparkle.sh")/bin/sign_update"
INFO="${APP}/Contents/Info.plist"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "${INFO}")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "${INFO}")"
MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw -o - "${INFO}")"

# Prints: sparkle:edSignature="..." length="..."
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  attributes="$(printf '%s' "${SPARKLE_ED_PRIVATE_KEY}" | "${SIGN_UPDATE}" --ed-key-file - "${DMG}")"
else
  attributes="$("${SIGN_UPDATE}" --account "${SPARKLE_KEY_ACCOUNT:-ScreenshotTool}" "${DMG}")"
fi
if [[ "${attributes}" != *"sparkle:edSignature="* ]]; then
  echo "make_macos_appcast: sign_update gave no signature" >&2
  exit 1
fi

cat > "${OUT}" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ScreenshotTool</title>
    <link>${PAGE}</link>
    <item>
      <title>ScreenshotTool ${VERSION}</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <link>${PAGE}</link>
      <sparkle:fullReleaseNotesLink>${PAGE}</sparkle:fullReleaseNotesLink>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_MACOS}</sparkle:minimumSystemVersion>
      <enclosure url="${URL}" ${attributes} type="application/x-apple-diskimage"/>
    </item>
  </channel>
</rss>
XML
echo "Appcast: ${OUT}"
