#!/usr/bin/env bash
# Screenshot ScreenshotTool's main screens under GNUstep's default theme and the Adwaita theme, on a
# private X display, for reviewing how each theme presents the app (#75).
#
# Usage: Tools/screenshots.sh [output-dir]          (default: screenshots/)
#   THEMES="default Adwaita"   the themes to use; "default" is GNUstep's own
#   SCREENSHOT_LIBRARY_DIR     a GNUstep Library folder holding Themes/ (default: the user's)
#   SCREENSHOT_WM              gnome-shell, openbox or none (default: the first one installed)
#   KEEP_WORK=1                keep the work folder (app logs, generated configuration)
#
# Needs Xvfb, xdotool and ImageMagick, and a window manager: GNOME Shell (as on GNOME desktops)
# when installed, otherwise Openbox; without either, windows have no title bars. The app runs with
# isolated GNUstep defaults (a private GNUSTEP_CONFIG_FILE), so the user's settings are untouched.
# Build the app first (make).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="$(mkdir -p "${1:-${ROOT_DIR}/screenshots}" && cd "${1:-${ROOT_DIR}/screenshots}" && pwd)"
THEMES="${THEMES:-default Adwaita}"
APP="${ROOT_DIR}/ScreenshotTool.app/ScreenshotTool"
WORK="$(mktemp -d)"
PIDS=()

GNUSTEP_ROOT="${GNUSTEP_ROOT:-/usr/GNUstep}"
if [[ -z "${GNUSTEP_MAKEFILES:-}" && -f "${GNUSTEP_ROOT}/System/Library/Makefiles/GNUstep.sh" ]]; then
  set +u
  # shellcheck disable=SC1091
  . "${GNUSTEP_ROOT}/System/Library/Makefiles/GNUstep.sh"
  set -u
fi

for tool in Xvfb xdotool xwininfo import convert; do
  command -v "${tool}" >/dev/null || { echo "screenshots: ${tool} is needed" >&2; exit 1; }
done
[[ -x "${APP}" ]] || { echo "screenshots: build the app first (make)" >&2; exit 1; }

cleanup() {
  stop_app
  for pid in "${PIDS[@]}"; do kill "${pid}" >/dev/null 2>&1 || true; done
  # dbus-run-session leaves the session's daemons running: stop those of this run.
  for pid in $(pgrep -u "$(id -u)" 2>/dev/null); do
    { tr '\0' '\n' <"/proc/${pid}/environ"; } 2>/dev/null | grep -qxF "XDG_RUNTIME_DIR=${WORK}/run" && kill "${pid}" 2>/dev/null
  done
  [[ -n "${KEEP_WORK:-}" ]] && echo "screenshots: kept ${WORK}" || rm -rf "${WORK}"
}
trap cleanup EXIT

# SIGKILL: on SIGTERM the app asks to save annotations and stays open. Its defaults are private.
stop_app() {
  for pid in $(pgrep -u "$(id -u)" 2>/dev/null); do
    [[ "$(readlink "/proc/${pid}/exe" 2>/dev/null)" == "${APP}" ]] && kill -KILL "${pid}" 2>/dev/null
  done
  sleep 1
}

# A free display, and a window manager on it.
for n in $(seq 140 170); do
  [[ ! -e "/tmp/.X11-unix/X${n}" && ! -e "/tmp/.X${n}-lock" ]] && break
done
export DISPLAY=":${n}"
Xvfb "${DISPLAY}" -screen 0 1600x1000x24 -nolisten tcp +extension GLX +extension RANDR >/dev/null 2>&1 &
PIDS+=($!)
sleep 1.5

WM="${SCREENSHOT_WM:-}"
if [[ -z "${WM}" ]]; then
  if command -v gnome-shell >/dev/null && command -v dbus-run-session >/dev/null; then
    WM=gnome-shell
  elif [[ "${WM}" == "openbox" ]]; then
    WM=openbox
  else
    WM=none
  fi
fi

if [[ "${WM}" == "gnome-shell" ]]; then
  mkdir -p "${WORK}"/{config,data,cache,state,run}
  chmod 700 "${WORK}/run"
  env -i HOME="${HOME}" PATH="${PATH}" DISPLAY="${DISPLAY}" XDG_CONFIG_HOME="${WORK}/config" \
    XDG_DATA_HOME="${WORK}/data" XDG_CACHE_HOME="${WORK}/cache" XDG_STATE_HOME="${WORK}/state" \
    XDG_RUNTIME_DIR="${WORK}/run" GSETTINGS_BACKEND=keyfile LIBGL_ALWAYS_SOFTWARE=1 \
    GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix \
    dbus-run-session -- gnome-shell --x11 >"${WORK}/wm.log" 2>&1 &
  PIDS+=($!)
  for _ in $(seq 1 60); do
    xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id" && break
    sleep 0.5
  done
  sleep 4
  # GNOME Shell starts in the overview: leave it.
  xdotool key Escape; sleep 1; xdotool key Escape; sleep 1
  echo "screenshots: window manager GNOME Shell"
elif command -v openbox >/dev/null; then
  openbox >"${WORK}/wm.log" 2>&1 &
  PIDS+=($!)
  sleep 2
  echo "screenshots: window manager Openbox"
else
  echo "screenshots: no window manager (GNOME Shell or Openbox); windows have no title bars" >&2
fi

# A sample image: a gradient, so the canvas and its surroundings are easy to tell apart.
convert -size 900x560 gradient:'#3b6ea8-#e8c37a' -define png:color-type=6 "PNG32:${WORK}/sample.png"

# The app's main window (the GNUstep client window, not the window manager's frame): x y width height.
client_geometry() {
  local name="$1" w
  for w in $(xdotool search --onlyvisible --name "${name}" 2>/dev/null); do
    local info
    info="$(xwininfo -id "${w}" 2>/dev/null)" || continue
    local width height
    width="$(awk '/Width:/ {print $2}' <<<"${info}")"
    height="$(awk '/Height:/ {print $2}' <<<"${info}")"
    if (( width >= 400 && height >= 300 )); then
      echo "$(awk '/Absolute upper-left X:/ {print $4}' <<<"${info}") $(awk '/Absolute upper-left Y:/ {print $4}' <<<"${info}") ${width} ${height}"
      return 0
    fi
  done
  return 1
}

wait_for_window() {
  local name="$1"
  for _ in $(seq 1 40); do
    client_geometry "${name}" >/dev/null && return 0
    sleep 0.5
  done
  return 1
}

shoot() {
  import -window root "${OUT_DIR}/$1.png"
  echo "screenshots: ${OUT_DIR}/$1.png"
}

launch() {
  local log="$1"; shift
  stop_app
  GNUSTEP_CONFIG_FILE="${CONFIG}" WAYLAND_DISPLAY= XDG_SESSION_TYPE=x11 SCREENSHOT_TOOL_LOG_PATH="${log}" \
    "${APP}" "$@" >/dev/null 2>&1 &
  sleep 1
}

for theme in ${THEMES}; do
  label="$(tr '[:upper:]' '[:lower:]' <<<"${theme}")"
  DEFAULTS="${WORK}/defaults-${label}"
  CONFIG="${WORK}/GNUstep-${label}.conf"
  mkdir -p "${DEFAULTS}"
  {
    grep -vE '^(GNUSTEP_USER_DEFAULTS_DIR|GNUSTEP_USER_CONFIG_FILE|GNUSTEP_USER_DIR_LIBRARY)=' \
      "${GNUSTEP_CONFIG_FILE:-/etc/GNUstep/GNUstep.conf}" 2>/dev/null
    echo "GNUSTEP_USER_DEFAULTS_DIR=${DEFAULTS}"
    echo "GNUSTEP_USER_CONFIG_FILE=${WORK}/.GNUstep.conf.unused"
    [[ -n "${SCREENSHOT_LIBRARY_DIR:-}" ]] && echo "GNUSTEP_USER_DIR_LIBRARY=${SCREENSHOT_LIBRARY_DIR}"
  } >"${CONFIG}"
  chmod 600 "${CONFIG}"
  if [[ "${label}" != "default" ]]; then
    # The theme, with its header bar (GNUstep draws the title bar), as GNOME users run it.
    printf '{\n  GSTheme = "%s";\n  GSX11HandlesWindowDecorations = NO;\n}\n' "${theme}" >"${DEFAULTS}/NSGlobalDomain.plist"
  fi
  LOG="${WORK}/app-${label}.log"

  # 1. No image: the empty state.
  launch "${LOG}"
  wait_for_window "ScreenshotTool" || { echo "screenshots: ${theme}: the window didn't appear" >&2; continue; }
  sleep 2
  shoot "${label}-empty"

  # 2. Preferences (the command key is Ctrl under Adwaita, Alt with GNUstep's defaults).
  xdotool key ctrl+comma; sleep 1.5
  xdotool search --onlyvisible --name "^Preferences$" >/dev/null 2>&1 || { xdotool key alt+comma; sleep 1.5; }
  # Drawing a new window under a theme can take several seconds on a virtual display.
  sleep 6
  shoot "${label}-preferences"

  # 3. An image.
  launch "${LOG}" "${WORK}/sample.png"
  wait_for_window "sample.png" || { echo "screenshots: ${theme}: the image window didn't appear" >&2; continue; }
  sleep 2
  shoot "${label}-image"
  read -r X Y W H < <(client_geometry "sample.png")

  # 4. The text toolbar: the text tool (T, a canvas shortcut), then a click on the canvas.
  xdotool mousemove $((X + W / 2)) $((Y + H / 2)) click 1; sleep 0.3
  xdotool key t
  for _ in $(seq 1 20); do
    tail -n 30 "${LOG}" 2>/dev/null | grep -q 'active=com.screenshottool.toolbar.text' && break
    sleep 0.25
  done
  sleep 0.5
  xdotool mousemove $((X + W / 3)) $((Y + H / 2)) click 1
  for _ in $(seq 1 20); do
    tail -n 30 "${LOG}" 2>/dev/null | grep -q 'showHUDMessage' && break
    sleep 0.25
  done
  # The text bar can take a few seconds to lay out.
  sleep 3
  xdotool type --delay 80 "Annotation"; sleep 1
  shoot "${label}-text-toolbar"

  # 5. The tool settings popover, from the colour control (the second toolbar item, at the same
  #    place in a toolbar row and in Adwaita's header bar), in a fresh window.
  launch "${LOG}" "${WORK}/sample.png"
  wait_for_window "sample.png" || { echo "screenshots: ${theme}: the image window didn't appear" >&2; continue; }
  sleep 2
  read -r X Y W H < <(client_geometry "sample.png")
  before="$(grep -c 'popover show invoked' "${LOG}" 2>/dev/null || true)"
  xdotool mousemove $((X + 316)) $((Y + 22)) click 1; sleep 1.5
  if [[ "$(grep -c 'popover show invoked' "${LOG}" 2>/dev/null || true)" == "${before}" ]]; then
    # Under GNUstep's default theme with window manager decorations, #60 clips the toolbar.
    echo "screenshots: ${theme}: the tool popover didn't open" >&2
  fi
  shoot "${label}-popover"
  stop_app
done
