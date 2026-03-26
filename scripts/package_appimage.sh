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
GNUSTEP_ROOT="${GNUSTEP_ROOT:-/usr/GNUstep}"

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "App bundle missing at ${APP_BUNDLE}. Build first with make -j\"$(nproc)\"." >&2
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
mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/lib" "${APPDIR}/usr/share/applications" "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

echo "Staging GNUstep bundle into ${APPDIR}..."
rsync -a --delete "${APP_BUNDLE}/" "${APPDIR}/usr/lib/ScreenshotTool.app/"

# Stage GNUstep runtime (libraries + themes) into the AppImage so it is self contained.
GNUSTEP_APPDIR_ROOT="${APPDIR}/usr/gnustep"
mkdir -p "${GNUSTEP_APPDIR_ROOT}/System"
if [[ -d "${GNUSTEP_ROOT}/System" ]]; then
  echo "Copying GNUstep runtime from ${GNUSTEP_ROOT}..."
  rsync -a "${GNUSTEP_ROOT}/System/" "${GNUSTEP_APPDIR_ROOT}/System/"
  # Duplicate libraries into the standard lib dir so the loader finds them without env tweaks.
  if [[ -d "${GNUSTEP_ROOT}/System/Library/Libraries" ]]; then
    rsync -a "${GNUSTEP_ROOT}/System/Library/Libraries/" "${APPDIR}/usr/lib/"
  fi
  if [[ -d "${GNUSTEP_ROOT}/lib" ]]; then
    rsync -a "${GNUSTEP_ROOT}/lib/" "${APPDIR}/usr/lib/"
  fi
  THEME_SRC="${GNUSTEP_ROOT}/System/Library/Themes/Sombre.theme"
  if [[ -d "${THEME_SRC}" ]]; then
    mkdir -p "${GNUSTEP_APPDIR_ROOT}/System/Library/Themes"
    rsync -a "${THEME_SRC}" "${GNUSTEP_APPDIR_ROOT}/System/Library/Themes/"
  fi
else
  echo "WARNING: GNUstep root not found at ${GNUSTEP_ROOT}; continuing without bundling runtime." >&2
fi

cat > "${APPDIR}/usr/bin/screenshottool" <<'EOF'
#!/usr/bin/env bash
SCRIPT_PATH="$0"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH" || echo "$SCRIPT_PATH")"
fi
HERE="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
APP_DIR="${HERE}/../lib/ScreenshotTool.app"
APP_LIB="${HERE}/../lib"
GNUSTEP_SYSTEM_ROOT="${HERE}/../gnustep/System"
export GNUSTEP_SYSTEM_ROOT
export LD_LIBRARY_PATH="${APP_LIB}:${GNUSTEP_SYSTEM_ROOT}/Library/Libraries:${LD_LIBRARY_PATH}"
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
export LD_LIBRARY_PATH="${APPDIR}/usr/lib:${GNUSTEP_ROOT}/System/Library/Libraries:${GNUSTEP_ROOT}/lib:${LD_LIBRARY_PATH:-}"
chmod -x "${APPDIR}/usr/bin/screenshottool"
pushd "${STAGING_DIR}" >/dev/null
env OUTPUT="${OUTPUT_NAME}" "${LINUXDEPLOY_BIN}" \
  --appdir="${APPDIR}" \
  --desktop-file="${APPDIR}/usr/share/applications/screenshottool.desktop" \
  --executable="${APPDIR}/usr/lib/ScreenshotTool.app/ScreenshotTool"
popd >/dev/null
chmod +x "${APPDIR}/usr/bin/screenshottool"

# Repackage with appimagetool after restoring the launcher executable bit so the
# resulting AppImage contains a runnable AppRun/screenshottool.
TEMP_APPIMAGE_DIR="$(mktemp -d)"
pushd "${TEMP_APPIMAGE_DIR}" >/dev/null
"${APPIMAGE_PLUGIN}" --appimage-extract >/dev/null
APPIMAGETOOL_BIN="${TEMP_APPIMAGE_DIR}/squashfs-root/usr/bin/appimagetool"
if [[ ! -x "${APPIMAGETOOL_BIN}" ]]; then
  echo "appimagetool missing after extracting ${APPIMAGE_PLUGIN}." >&2
  exit 1
fi
chmod +x "${APPIMAGETOOL_BIN}"
popd >/dev/null

rm -f "${STAGING_DIR:?}/${OUTPUT_NAME}"
"${APPIMAGETOOL_BIN}" "${APPDIR}" "${STAGING_DIR}/${OUTPUT_NAME}"
rm -rf "${TEMP_APPIMAGE_DIR}"

if [[ ! -f "${STAGING_DIR}/${OUTPUT_NAME}" ]]; then
  echo "appimagetool did not emit ${OUTPUT_NAME}; inspect output above." >&2
  exit 1
fi

mkdir -p "${STAGING_DIR}"
if [[ "${STAGING_DIR}/${OUTPUT_NAME}" != "${ARTIFACT}" ]]; then
  mv "${STAGING_DIR}/${OUTPUT_NAME}" "${ARTIFACT}"
fi
chmod +x "${ARTIFACT}"

echo "AppImage ready: ${ARTIFACT}"
sha256sum "${ARTIFACT}" || true
