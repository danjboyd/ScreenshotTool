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
LINUXDEPLOY_BIN="${LINUXDEPLOY:-linuxdeploy}"
APPIMAGE_PLUGIN="${LINUXDEPLOY_PLUGIN_APPIMAGE:-linuxdeploy-plugin-appimage}"
OUTPUT_NAME="${OUTPUT_NAME:-ScreenshotTool-x86_64.AppImage}"
GNUSTEP_ROOT="${GNUSTEP_ROOT:-/usr/GNUstep}"
ARTIFACT="${STAGING_DIR}/${OUTPUT_NAME}"
CHECKSUM_ARTIFACT="${ARTIFACT}.sha256"
DESKTOP_TEMPLATE="${ROOT_DIR}/packaging/linux/screenshottool.desktop"
APPSTREAM_TEMPLATE="${ROOT_DIR}/packaging/linux/screenshottool.appdata.xml"
APP_ID="io.github.danjboyd.ScreenshotTool"
DESKTOP_FILE_PATH="${APPDIR}/usr/share/applications/${APP_ID}.desktop"
APPSTREAM_FILE_PATH="${APPDIR}/usr/share/metainfo/${APP_ID}.appdata.xml"

# linuxdeploy and the plugin are distributed as AppImages; extracting and
# running them avoids host FUSE configuration differences in CI and locally.
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"

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
mkdir -p "${APPDIR}/usr/bin" \
         "${APPDIR}/usr/lib" \
         "${APPDIR}/usr/share/applications" \
         "${APPDIR}/usr/share/icons/hicolor/256x256/apps" \
         "${APPDIR}/usr/share/metainfo"

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
GNUSTEP_ROOT="${HERE}/../gnustep"
GNUSTEP_SYSTEM_ROOT="${GNUSTEP_ROOT}/System"
GNUSTEP_LOCAL_ROOT="${GNUSTEP_SYSTEM_ROOT}"
GNUSTEP_NETWORK_ROOT="${GNUSTEP_SYSTEM_ROOT}"
GNUSTEP_MAKEFILES="${GNUSTEP_SYSTEM_ROOT}/Library/Makefiles"
GNUSTEP_USER_CONFIG_FILE=
RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
if [[ -z "${RUNTIME_DIR}" ]]; then
  RUNTIME_DIR=/tmp
fi
CONFIG_DIR="${RUNTIME_DIR}/screenshottool-gnustep-${UID:-$(id -u)}"
mkdir -p "${CONFIG_DIR}"
chmod 0700 "${CONFIG_DIR}" 2>/dev/null || true
GNUSTEP_CONFIG_FILE="${CONFIG_DIR}/GNUstep.conf"
cat > "${GNUSTEP_CONFIG_FILE}" <<EOF_CONFIG
GNUSTEP_USER_CONFIG_FILE=
GNUSTEP_USER_DEFAULTS_DIR=GNUstep/Defaults
GNUSTEP_MAKEFILES="${GNUSTEP_SYSTEM_ROOT}/Library/Makefiles"
GNUSTEP_SYSTEM_USERS_DIR=/home
GNUSTEP_NETWORK_USERS_DIR=/home
GNUSTEP_LOCAL_USERS_DIR=/home

GNUSTEP_SYSTEM_APPS="${GNUSTEP_SYSTEM_ROOT}/Applications"
GNUSTEP_SYSTEM_ADMIN_APPS="${GNUSTEP_SYSTEM_ROOT}/Applications/Admin"
GNUSTEP_SYSTEM_WEB_APPS="${GNUSTEP_SYSTEM_ROOT}/Library/WebApplications"
GNUSTEP_SYSTEM_TOOLS="${GNUSTEP_SYSTEM_ROOT}/Tools"
GNUSTEP_SYSTEM_ADMIN_TOOLS="${GNUSTEP_SYSTEM_ROOT}/Tools/Admin"
GNUSTEP_SYSTEM_LIBRARY="${GNUSTEP_SYSTEM_ROOT}/Library"
GNUSTEP_SYSTEM_HEADERS="${GNUSTEP_SYSTEM_ROOT}/Library/Headers"
GNUSTEP_SYSTEM_LIBRARIES="${GNUSTEP_SYSTEM_ROOT}/Library/Libraries"
GNUSTEP_SYSTEM_DOC="${GNUSTEP_SYSTEM_ROOT}/Library/Documentation"
GNUSTEP_SYSTEM_DOC_MAN="${GNUSTEP_SYSTEM_ROOT}/Library/Documentation/man"
GNUSTEP_SYSTEM_DOC_INFO="${GNUSTEP_SYSTEM_ROOT}/Library/Documentation/info"

GNUSTEP_NETWORK_APPS="${GNUSTEP_SYSTEM_ROOT}/Applications"
GNUSTEP_NETWORK_ADMIN_APPS="${GNUSTEP_SYSTEM_ROOT}/Applications/Admin"
GNUSTEP_NETWORK_WEB_APPS="${GNUSTEP_SYSTEM_ROOT}/Library/WebApplications"
GNUSTEP_NETWORK_TOOLS="${GNUSTEP_SYSTEM_ROOT}/Tools"
GNUSTEP_NETWORK_ADMIN_TOOLS="${GNUSTEP_SYSTEM_ROOT}/Tools/Admin"
GNUSTEP_NETWORK_LIBRARY="${GNUSTEP_SYSTEM_ROOT}/Library"
GNUSTEP_NETWORK_HEADERS="${GNUSTEP_SYSTEM_ROOT}/Library/Headers"
GNUSTEP_NETWORK_LIBRARIES="${GNUSTEP_SYSTEM_ROOT}/Library/Libraries"
GNUSTEP_NETWORK_DOC="${GNUSTEP_SYSTEM_ROOT}/Library/Documentation"
GNUSTEP_NETWORK_DOC_MAN="${GNUSTEP_SYSTEM_ROOT}/Library/Documentation/man"
GNUSTEP_NETWORK_DOC_INFO="${GNUSTEP_SYSTEM_ROOT}/Library/Documentation/info"

GNUSTEP_LOCAL_APPS="${GNUSTEP_SYSTEM_ROOT}/Applications"
GNUSTEP_LOCAL_ADMIN_APPS="${GNUSTEP_SYSTEM_ROOT}/Applications/Admin"
GNUSTEP_LOCAL_WEB_APPS="${GNUSTEP_SYSTEM_ROOT}/Library/WebApplications"
GNUSTEP_LOCAL_TOOLS="${GNUSTEP_SYSTEM_ROOT}/Tools"
GNUSTEP_LOCAL_ADMIN_TOOLS="${GNUSTEP_SYSTEM_ROOT}/Tools/Admin"
GNUSTEP_LOCAL_LIBRARY="${GNUSTEP_SYSTEM_ROOT}/Library"
GNUSTEP_LOCAL_HEADERS="${GNUSTEP_SYSTEM_ROOT}/Library/Headers"
GNUSTEP_LOCAL_LIBRARIES="${GNUSTEP_SYSTEM_ROOT}/Library/Libraries"
GNUSTEP_LOCAL_DOC="${GNUSTEP_SYSTEM_ROOT}/Library/Documentation"
GNUSTEP_LOCAL_DOC_MAN="${GNUSTEP_SYSTEM_ROOT}/Library/Documentation/man"
GNUSTEP_LOCAL_DOC_INFO="${GNUSTEP_SYSTEM_ROOT}/Library/Documentation/info"

GNUSTEP_USER_DIR_APPS=GNUstep/Applications
GNUSTEP_USER_DIR_ADMIN_APPS=GNUstep/Applications/Admin
GNUSTEP_USER_DIR_WEB_APPS=GNUstep/Library/WebApplications
GNUSTEP_USER_DIR_TOOLS=GNUstep/Tools
GNUSTEP_USER_DIR_ADMIN_TOOLS=GNUstep/Tools/Admin
GNUSTEP_USER_DIR_LIBRARY=GNUstep/Library
GNUSTEP_USER_DIR_HEADERS=GNUstep/Library/Headers
GNUSTEP_USER_DIR_LIBRARIES=GNUstep/Library/Libraries
GNUSTEP_USER_DIR_DOC=GNUstep/Library/Documentation
GNUSTEP_USER_DIR_DOC_MAN=GNUstep/Library/Documentation/man
GNUSTEP_USER_DIR_DOC_INFO=GNUstep/Library/Documentation/info
EOF_CONFIG
chmod 0644 "${GNUSTEP_CONFIG_FILE}"
export GNUSTEP_SYSTEM_ROOT GNUSTEP_LOCAL_ROOT GNUSTEP_NETWORK_ROOT
export GNUSTEP_CONFIG_FILE GNUSTEP_MAKEFILES GNUSTEP_USER_CONFIG_FILE
if [[ -f "${GNUSTEP_MAKEFILES}/GNUstep.sh" ]]; then
  set +u
  . "${GNUSTEP_MAKEFILES}/GNUstep.sh"
  set -u
fi
export GNUSTEP_SYSTEM_ROOT GNUSTEP_LOCAL_ROOT GNUSTEP_NETWORK_ROOT
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
  export LD_LIBRARY_PATH="${APP_LIB}:${LD_LIBRARY_PATH}"
else
  export LD_LIBRARY_PATH="${APP_LIB}"
fi
exec "${APP_DIR}/ScreenshotTool" "$@"
EOF
chmod +x "${APPDIR}/usr/bin/screenshottool"

if [[ -f "${DESKTOP_TEMPLATE}" ]]; then
  install -m 0644 "${DESKTOP_TEMPLATE}" "${DESKTOP_FILE_PATH}"
else
  cat > "${DESKTOP_FILE_PATH}" <<'EOF'
[Desktop Entry]
Type=Application
Name=ScreenshotTool
Comment=Annotate images with pen, highlighter, and text tools
Exec=screenshottool %U
Icon=screenshottool
Categories=Graphics;
StartupWMClass=ScreenshotTool
Terminal=false
EOF
fi

if [[ -f "${APPSTREAM_TEMPLATE}" ]]; then
  install -m 0644 "${APPSTREAM_TEMPLATE}" "${APPSTREAM_FILE_PATH}"
fi

ICON_SRC="${APP_BUNDLE}/Resources/ScreenshotToolIcon.png"
if [[ -f "${ICON_SRC}" ]]; then
  install -m 0644 "${ICON_SRC}" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/screenshottool.png"
fi

echo "Running linuxdeploy..."
chmod +x "${LINUXDEPLOY_BIN}" "${APPIMAGE_PLUGIN}" 2>/dev/null || true
export LD_LIBRARY_PATH="${APPDIR}/usr/lib:${GNUSTEP_ROOT}/System/Library/Libraries:${GNUSTEP_ROOT}/lib:${LD_LIBRARY_PATH:-}"
BACKEND_DEPLOY_ARGS=()
for backend_bundle in "${APPDIR}"/usr/gnustep/System/Library/Bundles/libgnustep-back*.bundle/libgnustep-back*; do
  if [[ -f "${backend_bundle}" ]]; then
    BACKEND_DEPLOY_ARGS+=( "--deploy-deps-only=${backend_bundle}" )
  fi
done
chmod -x "${APPDIR}/usr/bin/screenshottool"
pushd "${STAGING_DIR}" >/dev/null
env OUTPUT="${OUTPUT_NAME}" "${LINUXDEPLOY_BIN}" \
  --appdir="${APPDIR}" \
  --desktop-file="${DESKTOP_FILE_PATH}" \
  --executable="${APPDIR}/usr/lib/ScreenshotTool.app/ScreenshotTool" \
  "${BACKEND_DEPLOY_ARGS[@]}"
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

rm -f "${ARTIFACT}" "${CHECKSUM_ARTIFACT}"
"${APPIMAGETOOL_BIN}" "${APPDIR}" "${STAGING_DIR}/${OUTPUT_NAME}"
rm -rf "${TEMP_APPIMAGE_DIR}"

if [[ ! -f "${ARTIFACT}" ]]; then
  echo "appimagetool did not emit ${OUTPUT_NAME}; inspect output above." >&2
  exit 1
fi

mkdir -p "${STAGING_DIR}"
chmod +x "${ARTIFACT}"

echo "AppImage ready: ${ARTIFACT}"
sha256sum "${ARTIFACT}" | tee "${CHECKSUM_ARTIFACT}" || true
