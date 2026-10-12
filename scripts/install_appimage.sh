#!/usr/bin/env bash
# Install the released Linux AppImage for everyday use, with a desktop entry and icon.
#
# Usage: scripts/install_appimage.sh [--channel stable|prerelease] [--dir DIR] [--uninstall]
#
#   --channel     the update feed to install from (default: stable). The AppImage checks the feed
#                 of the channel it was released on, so this also picks what it updates to.
#   --dir         where the AppImage goes (default: ~/Applications). It has to stay writable: the
#                 updater replaces the file in place.
#   --uninstall   remove the AppImage, desktop entry and icon. Settings stay in
#                 ~/GNUstep/Defaults/com.danboyd.screenshottool.plist.
#
# The desktop entry is named "ScreenshotTool". A build from the tree keeps its own entry
# (scripts/install-gnome-desktop-entry.sh, "ScreenshotTool (Dev)") and its own settings
# (GNUmakefile's ST_DEV_BUILD).

set -euo pipefail

FEED_BASE="https://danjboyd.github.io/ScreenshotTool/updates/linux"
APP_ID="io.github.danjboyd.ScreenshotTool"
CHANNEL="stable"
INSTALL_DIR="${HOME}/Applications"
UNINSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="${2:?--channel needs a value}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:?--dir needs a value}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "${CHANNEL}" in
  stable|prerelease) ;;
  *) echo "--channel is stable or prerelease, not ${CHANNEL}" >&2; exit 2 ;;
esac

DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
APPIMAGE="${INSTALL_DIR}/ScreenshotTool.AppImage"
DESKTOP_FILE="${DATA_HOME}/applications/${APP_ID}.desktop"
# The icon is 1024x1024; hicolor has no bigger size than 512, and GTK scales it.
ICON_FILE="${DATA_HOME}/icons/hicolor/512x512/apps/${APP_ID}.png"

refresh_desktop_caches() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${DATA_HOME}/applications" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -f "${DATA_HOME}/icons/hicolor/index.theme" ]]; then
    gtk-update-icon-cache -q -t "${DATA_HOME}/icons/hicolor" || true
  fi
}

if [[ "${UNINSTALL}" == 1 ]]; then
  rm -f -- "${APPIMAGE}" "${DESKTOP_FILE}" "${ICON_FILE}"
  refresh_desktop_caches
  echo "Removed ${APPIMAGE}, ${DESKTOP_FILE} and ${ICON_FILE}."
  exit 0
fi

for tool in curl jq sha256sum; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "${tool} is required." >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

FEED_URL="${FEED_BASE}/${CHANNEL}.json"
if ! curl -fsSL "${FEED_URL}" -o "${WORK_DIR}/feed.json"; then
  echo "Couldn't read the ${CHANNEL} feed at ${FEED_URL}." >&2
  if [[ "${CHANNEL}" == stable ]]; then
    echo "There may be no stable release yet: tag one (vX.Y.Z), or use --channel prerelease." >&2
  fi
  exit 1
fi

# The feed's newest release, and its AppImage.
read -r VERSION ASSET_URL ASSET_SHA256 < <(jq -r '
  .releases[0] as $r
  | ($r.assets[] | select(.kind == "appimage")) as $a
  | "\($r.version) \($a.url) \($a.sha256)"' "${WORK_DIR}/feed.json")
if [[ -z "${ASSET_URL:-}" || "${ASSET_URL}" == null ]]; then
  echo "The ${CHANNEL} feed lists no AppImage." >&2
  exit 1
fi

echo "Downloading ScreenshotTool ${VERSION} (${CHANNEL})..."
mkdir -p "${INSTALL_DIR}"
# Next to the destination, so the move below replaces the file in one step.
DOWNLOAD="${INSTALL_DIR}/.ScreenshotTool.AppImage.download"
curl -fL --progress-bar "${ASSET_URL}" -o "${DOWNLOAD}"
if ! echo "${ASSET_SHA256}  ${DOWNLOAD}" | sha256sum -c --quiet -; then
  rm -f -- "${DOWNLOAD}"
  echo "The download doesn't match the feed's SHA-256." >&2
  exit 1
fi
chmod 755 "${DOWNLOAD}"
mv -f -- "${DOWNLOAD}" "${APPIMAGE}"

# The icon is at the AppImage's root, the updater's config in its metadata. --appimage-extract
# needs no FUSE.
UPDATE_CONFIG="usr/metadata/updates/gnustep-packager-update.json"
for path in "${APP_ID}.png" "${UPDATE_CONFIG}"; do
  (cd "${WORK_DIR}" && "${APPIMAGE}" --appimage-extract "${path}" >/dev/null)
done
mkdir -p "$(dirname "${ICON_FILE}")" "$(dirname "${DESKTOP_FILE}")"
install -m 644 "${WORK_DIR}/squashfs-root/${APP_ID}.png" "${ICON_FILE}"

# Exec takes absolute paths (%F): AppRun changes to the bundle's directory before it starts the app.
cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=ScreenshotTool
Comment=Annotate screenshots and other images with pen, highlighter, and text tools
Exec="${APPIMAGE}" %F
TryExec=${APPIMAGE}
Icon=${APP_ID}
Terminal=false
StartupNotify=true
StartupWMClass=ScreenshotTool
Categories=Graphics;
Keywords=screenshot;annotation;markup;image;
MimeType=image/png;image/jpeg;image/webp;image/tiff;
Actions=take-screenshot;

[Desktop Action take-screenshot]
Name=Take Screenshot
Exec="${APPIMAGE}" --capture
EOF
chmod 644 "${DESKTOP_FILE}"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "${DESKTOP_FILE}"
fi
refresh_desktop_caches

echo "Installed ScreenshotTool ${VERSION} at ${APPIMAGE}."
# What the app checks is what its release packaged, not the feed it was installed from: an rc
# built before the prerelease feed existed (#111) checks the stable one.
CHECKED_FEED="$(jq -r '.updates.feedUrl // empty' "${WORK_DIR}/squashfs-root/${UPDATE_CONFIG}" 2>/dev/null || true)"
echo "It checks ${CHECKED_FEED:-an unknown feed} for updates."
