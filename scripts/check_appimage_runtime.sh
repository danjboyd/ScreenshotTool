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
# 3. A new window's process, as Paste as New Image and Take Screenshot start it, starts and runs
#    on the AppImage's GNUstep too. 0.3.3 started it through the host's openapp, which failed.
# 4. With a host GNUstep's gpbs already running (started here when the host has one), the app
#    still copies through its own: 0.3.3 used the host's, and with an older one Copy offered no
#    image/png. The app copies its image at launch for this (SCREENSHOT_TOOL_SMOKE_NEW_WINDOW).

set -euo pipefail

APPIMAGE_PATH="${1:?usage: $0 <AppImage> [image]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_PATH="${2:-${ROOT_DIR}/Resources/ScreenshotToolIcon.png}"
APPIMAGE_PATH="$(cd "$(dirname "${APPIMAGE_PATH}")" && pwd)/$(basename "${APPIMAGE_PATH}")"

WORK_DIR="$(mktemp -d)"
APP_PID=""
SECOND_PID=""
HOST_GPBS_PID=""
cleanup() {
  local pid
  for pid in "${APP_PID}" "${SECOND_PID}" "${launcher:-}" "${HOST_GPBS_PID}"; do
    if [[ -n "${pid}" ]]; then
      kill -9 "${pid}" 2>/dev/null || true
    fi
  done
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

# 4, set up: a host gpbs, started the way a host GNUstep app starts it (no private TMP).
host_gpbs=""
for candidate in /usr/GNUstep/System/Tools/gpbs /usr/GNUstep/Local/Tools/gpbs /usr/bin/gpbs; do
  if [[ -x "${candidate}" ]]; then
    host_gpbs="${candidate}"
    break
  fi
done
# host_gpbs_running: the PID of a gpbs that isn't the AppImage's, if one runs.
host_gpbs_running() {
  local proc exe
  for proc in /proc/[0-9]*; do
    exe="$(readlink "${proc}/exe" 2>/dev/null || true)"
    if [[ "${exe}" == */gpbs && ( -z "${app_root:-}" || "${exe}" != "${app_root}/"* ) ]]; then
      echo "${proc#/proc/}"
      return
    fi
  done
}
if [[ -n "${host_gpbs}" && -z "$(host_gpbs_running)" ]]; then
  # With its own GNUstep's environment, as a host app starts it. (If one already runs, it serves.)
  host_env="${host_gpbs%/System/Tools/gpbs}/System/Library/Makefiles/GNUstep.sh"
  env -u TMP -u TEMP -u GNUSTEP_CONFIG_FILE -u LD_LIBRARY_PATH bash -c \
    '[[ -f "$1" ]] && . "$1" >/dev/null 2>&1; exec "$2" --no-fork' bash "${host_env}" "${host_gpbs}" \
    >"${WORK_DIR}/host-gpbs.log" 2>&1 &
  HOST_GPBS_PID=$!
  disown "${HOST_GPBS_PID}"
  sleep 2
fi
host_gpbs_pid="$(host_gpbs_running)"

# 2. What the running app maps. The image it opens a new window for (3) is a copy, under another
# name, so the new window doesn't start one more.
SECOND_IMAGE="${WORK_DIR}/second-window.png"
cp "${IMAGE_PATH}" "${SECOND_IMAGE}"
LOG_PATH="${WORK_DIR}/app.log"
APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}" SCREENSHOT_TOOL_LOG_PATH="${LOG_PATH}" \
  SCREENSHOT_TOOL_SMOKE_NEW_WINDOW="${SECOND_IMAGE}" \
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

# check_maps <pid> <what>: fails unless every GNUstep piece <pid> maps comes from the AppImage.
check_maps() {
  local mapped gnustep_mapped outside
  mapped="$(awk '{print $6}' "/proc/$1/maps" | grep '^/' | sort -u)"
  gnustep_mapped="$(grep -E 'gnustep|objc|dispatch|BlocksRuntime|\.bundle/|\.theme/' <<<"${mapped}" || true)"
  outside="$(grep -v -F -- "${app_root}/" <<<"${gnustep_mapped}" || true)"
  if [[ -z "${gnustep_mapped}" ]]; then
    echo "Found no GNUstep libraries in $2's mappings: the check can't tell anything." >&2
    failed=1
  elif [[ -n "${outside}" ]]; then
    echo "$2 maps GNUstep from outside the AppImage (${app_root}):" >&2
    sed 's/^/  /' <<<"${outside}" >&2
    failed=1
  else
    echo "$2 maps all $(wc -l <<<"${gnustep_mapped}") of its GNUstep libraries, backend and theme from the AppImage:"
    sed "s|^${app_root}/|  |" <<<"${gnustep_mapped}"
  fi
}
check_maps "${APP_PID}" "The app"

# 3. The new window's process: the AppImage's executable, opening the copy.
for _ in $(seq 1 40); do
  for proc in /proc/[0-9]*; do
    pid="${proc#/proc/}"
    [[ "${pid}" == "${APP_PID}" ]] && continue
    candidate="$(readlink "${proc}/exe" 2>/dev/null || true)"
    if [[ "${candidate}" == "${app_root}/"*/ScreenshotTool.app/ScreenshotTool ]] &&
       tr '\0' '\n' <"${proc}/cmdline" 2>/dev/null | grep -q -F -x -- "${SECOND_IMAGE}"; then
      SECOND_PID="${pid}"
      break 2
    fi
  done
  sleep 0.5
done
if [[ -z "${SECOND_PID}" ]]; then
  echo "No new window's process started from the AppImage (Paste as New Image would open nothing). Its log:" >&2
  grep -E 'pasteAsNewImage' "${LOG_PATH}" >&2 2>/dev/null || true
  failed=1
else
  sleep 3
  if [[ -d "/proc/${SECOND_PID}" ]]; then
    check_maps "${SECOND_PID}" "The new window's process"
  else
    echo "The new window's process exited at once." >&2
    failed=1
  fi
fi

# 4. The app's own gpbs, though a host one was running.
if [[ -n "${host_gpbs_pid}" ]]; then
  own_gpbs=""
  for _ in $(seq 1 20); do
    for proc in /proc/[0-9]*; do
      if [[ "$(readlink "${proc}/exe" 2>/dev/null || true)" == "${app_root}/"*/gpbs ]]; then
        own_gpbs="${proc#/proc/}"
        break 2
      fi
    done
    sleep 0.5
  done
  if [[ -n "${own_gpbs}" ]]; then
    echo "With a host gpbs running (pid ${host_gpbs_pid}), the app started its own (pid ${own_gpbs})."
    if command -v xclip >/dev/null 2>&1; then
      targets="$(timeout 10 xclip -selection clipboard -t TARGETS -o 2>/dev/null || true)"
      if grep -q -x 'image/png' <<<"${targets}"; then
        echo "Its Copy offers image/png."
      else
        echo "Its Copy offers no image/png (targets: $(tr '\n' ' ' <<<"${targets}"))." >&2
        failed=1
      fi
    fi
    kill -9 "${own_gpbs}" 2>/dev/null || true
  else
    echo "With a host gpbs running (pid ${host_gpbs_pid}), the app used it instead of its own." >&2
    failed=1
  fi
else
  echo "No host gpbs could be started: skipped the check that the app uses its own."
  [[ -s "${WORK_DIR}/host-gpbs.log" ]] && sed 's/^/  /' "${WORK_DIR}/host-gpbs.log"
fi

exit "${failed}"
