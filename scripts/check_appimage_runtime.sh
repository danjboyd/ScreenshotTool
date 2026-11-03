#!/usr/bin/env bash
# Checks that an AppImage runs on its own GNUstep, not the host's.
#
#   scripts/check_appimage_runtime.sh <AppImage> [image]
#
# 1. The bundled libs-back has the Adwaita theme's series (scripts/patches): window types, the
#    32-bit visual, window shadows with rounded corners, and popover shadows. 0.3.3 shipped a
#    libs-back without it and its windows were square, with no error anywhere.
# 2. Launched (it needs an X display: run it under xvfb-run), the app maps every GNUstep, objc and
#    libdispatch library, its backend bundle and its theme from inside the AppImage. A host with
#    GNUstep installed (the CI runner has /usr/GNUstep) is where a leak would show.

set -euo pipefail

APPIMAGE_PATH="${1:?usage: $0 <AppImage> [image]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_PATH="${2:-${ROOT_DIR}/Resources/ScreenshotToolIcon.png}"
APPIMAGE_PATH="$(cd "$(dirname "${APPIMAGE_PATH}")" && pwd)/$(basename "${APPIMAGE_PATH}")"

WORK_DIR="$(mktemp -d)"
APP_PID=""
cleanup() {
  if [[ -n "${APP_PID}" ]]; then
    kill -9 "${APP_PID}" 2>/dev/null || true
  fi
  kill -9 "${launcher:-}" 2>/dev/null || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

failed=0

# 1. The carried libs-back patches, by the defaults and atoms each one adds.
(cd "${WORK_DIR}" && "${APPIMAGE_PATH}" --appimage-extract >/dev/null)
back="$(find "${WORK_DIR}/squashfs-root" -path '*libgnustep-back-*.bundle/libgnustep-back-*' -type f -print -quit)"
if [[ -z "${back}" ]]; then
  echo "No libgnustep-back bundle in ${APPIMAGE_PATH}" >&2
  exit 1
fi
# What only the patched libs-back has: window types (_setWindowType:), the 32-bit visual, window
# shadows with rounded corners (and the _GTK_FRAME_EXTENTS they publish), and popover shadows. The
# Motif hints, WM_DELETE_WINDOW and XDND patches add no string of their own; the Alt+F4 check
# covers WM_DELETE_WINDOW.
# (Read once: grep -q in a pipe would stop strings early, and pipefail would count that a miss.)
back_strings="$(strings -a "${back}")"
for key in _setWindowType: GSBackBorderlessWindowAlpha GSBackWindowShadows GSBackWindowCornerRadius \
           _GTK_FRAME_EXTENTS GSBackPopoverShadows; do
  if ! grep -q -F -x -- "${key}" <<<"${back_strings}"; then
    echo "The bundled libs-back lacks ${key}: a carried patch is missing (${back#"${WORK_DIR}/squashfs-root/"})" >&2
    failed=1
  fi
done
[[ "${failed}" -eq 0 ]] && echo "The bundled libs-back has the carried patches."

# 2. What the running app maps.
LOG_PATH="${WORK_DIR}/app.log"
APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}" SCREENSHOT_TOOL_LOG_PATH="${LOG_PATH}" \
  "${APPIMAGE_PATH}" "${IMAGE_PATH}" >"${WORK_DIR}/stdout.log" 2>&1 &
launcher=$!
disown "${launcher}"
for _ in $(seq 1 60); do
  if grep -q "openImageAtURL loaded" "${LOG_PATH}" 2>/dev/null; then
    break
  fi
  sleep 0.5
done
# The app is the launcher itself (AppRun execs it) or, with APPIMAGE_EXTRACT_AND_RUN or an AppRun
# that doesn't exec, a descendant of it.
descendants() {
  local pid
  echo "$1"
  for pid in $(pgrep -P "$1" 2>/dev/null); do
    descendants "${pid}"
  done
}
exe=""
for _ in $(seq 1 20); do
  for pid in $(descendants "${launcher}"); do
    candidate="$(readlink "/proc/${pid}/exe" 2>/dev/null || true)"
    if [[ "${candidate}" == */usr/*/ScreenshotTool.app/ScreenshotTool ]]; then
      APP_PID="${pid}"
      exe="${candidate}"
      break 2
    fi
  done
  sleep 0.5
done
if [[ -z "${APP_PID}" ]]; then
  echo "The app didn't start from the AppImage. Recent output:" >&2
  tail -n 20 "${WORK_DIR}/stdout.log" "${LOG_PATH}" >&2 2>/dev/null || true
  exit 1
fi
# The AppDir: everything above usr/ (usr/app in gnustep-packager's AppImage, usr/lib in
# scripts/package_appimage.sh's).
app_root="${exe%/usr/*/ScreenshotTool.app/ScreenshotTool}"

mapped="$(awk '{print $6}' "/proc/${APP_PID}/maps" | grep '^/' | sort -u)"
gnustep_mapped="$(grep -E 'gnustep|objc|dispatch|BlocksRuntime|\.bundle/|\.theme/' <<<"${mapped}" || true)"
outside="$(grep -v -F -- "${app_root}/" <<<"${gnustep_mapped}" || true)"
if [[ -z "${gnustep_mapped}" ]]; then
  echo "Found no GNUstep libraries in the app's mappings: the check can't tell anything." >&2
  failed=1
elif [[ -n "${outside}" ]]; then
  echo "The app maps GNUstep from outside the AppImage (${app_root}):" >&2
  sed 's/^/  /' <<<"${outside}" >&2
  failed=1
else
  echo "The app maps all $(wc -l <<<"${gnustep_mapped}") of its GNUstep libraries, backend and theme from the AppImage:"
  sed "s|^${app_root}/|  |" <<<"${gnustep_mapped}"
fi

exit "${failed}"
