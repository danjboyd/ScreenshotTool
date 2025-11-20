#!/usr/bin/env bash
# Package ScreenshotTool as an AppImage (Debian/Ubuntu hosts).

set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This packager runs on Linux hosts. Use scripts/package_macos_dmg.sh on macOS." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE="${ROOT_DIR}/ScreenshotTool.app"
STAGING_DIR="${ROOT_DIR}/Staging"
APPDIR="${STAGING_DIR}/AppDir"
ARTIFACT="${STAGING_DIR}/ScreenshotTool-x86_64.AppImage"
LINUXDEPLOY_BIN="${LINUXDEPLOY:-linuxdeploy}"
APPIMAGE_PLUGIN="${LINUXDEPLOY_PLUGIN_APPIMAGE:-linuxdeploy-plugin-appimage}"
OUTPUT_NAME="${OUTPUT_NAME:-ScreenshotTool-x86_64.AppImage}"

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "App bundle missing at ${APP_BUNDLE}. Build first (make -j or scripts/build_macos.sh equivalent on Linux)." >&2
  exit 1
fi

if ! command -v "${LINUXDEPLOY_BIN}" >/dev/null 2>&1; then
  echo "linuxdeploy not found (set LINUXDEPLOY=/path/to/linuxdeploy-x86_64.AppImage)." >&2
  exit 1
fi

if ! command -v "${APPIMAGE_PLUGIN}" >/dev/null 2>&1; then
  echo "linuxdeploy AppImage plugin not found (set LINUXDEPLOY_PLUGIN_APPIMAGE=/path/to/linuxdeploy-plugin-appimage-x86_64.AppImage)." >&2
  exit 1
fi
export LINUXDEPLOY_PLUGIN_APPIMAGE="${APPIMAGE_PLUGIN}"

rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/share/applications" "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

echo "Staging GNUstep bundle into ${APPDIR}..."
rsync -a --delete "${APP_BUNDLE}/" "${APPDIR}/usr/lib/ScreenshotTool.app/"

cat > "${APPDIR}/usr/bin/screenshottool" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${HERE}/../lib/ScreenshotTool.app"
exec "${APP_DIR}/ScreenshotTool" "$@"
EOF
chmod +x "${APPDIR}/usr/bin/screenshottool"

cat > "${APPDIR}/usr/share/applications/screenshottool.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=ScreenshotTool
Comment=Annotate images with pen, highlighter, and text tools
Exec=screenshottool %U
Icon=screenshottool
Categories=Graphics;
EOF

ICON_SRC="${APP_BUNDLE}/Resources/ScreenshotToolIcon.png"
if [[ -f "${ICON_SRC}" ]]; then
  install -m 0644 "${ICON_SRC}" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/screenshottool.png"
fi

echo "Running linuxdeploy..."
chmod +x "${LINUXDEPLOY_BIN}" "${APPIMAGE_PLUGIN}" 2>/dev/null || true
pushd "${STAGING_DIR}" >/dev/null
env OUTPUT="${OUTPUT_NAME}" "${LINUXDEPLOY_BIN}" --appdir="${APPDIR}" --desktop-file="${APPDIR}/usr/share/applications/screenshottool.desktop" --executable="${APPDIR}/usr/bin/screenshottool" -o appimage
popd >/dev/null

if [[ ! -f "${STAGING_DIR}/${OUTPUT_NAME}" ]]; then
  echo "linuxdeploy did not emit ${OUTPUT_NAME}; inspect linuxdeploy output above." >&2
  exit 1
fi

mkdir -p "${STAGING_DIR}"
mv "${STAGING_DIR}/${OUTPUT_NAME}" "${ARTIFACT}"
chmod +x "${ARTIFACT}"

echo "AppImage ready: ${ARTIFACT}"
sha256sum "${ARTIFACT}" || true
