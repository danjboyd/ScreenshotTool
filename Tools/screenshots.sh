#!/usr/bin/env bash
# Screenshot ScreenshotTool's main screens under GNUstep's default theme and the Adwaita theme, on a
# private X display, for reviewing how each theme presents the app (#75).
#
# Usage: Tools/screenshots.sh [output-dir]          (default: screenshots/)
#   THEMES="default Adwaita"   the themes to use; "default" is GNUstep's own
#   SCREENSHOT_LIBRARY_DIR     a GNUstep Library folder holding Themes/ (default: the user's)
#   SCREENSHOT_WM              gnome-shell, openbox or none (default: the first one installed)
#   SCREENSHOT_SAMPLE          the image to open (default: a generated chart)
#   KEEP_WORK=1                keep the work folder (app logs, generated configuration)
#
# Each shot is saved twice: <name>.png, the whole screen, and <name>-window.png, cropped to the
# window it's about (with the window manager's title bar, when it draws one). The README's images
# come from the -window shots (#81).
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

# A sample image: the one asked for, or a simple chart, as a screenshot to mark up might show.
# Either way it's sample.png, the title the script looks for.
if [[ -n "${SCREENSHOT_SAMPLE:-}" ]]; then
  convert "${SCREENSHOT_SAMPLE}" -define png:color-type=6 "PNG32:${WORK}/sample.png"
else
  bars=(140 190 120 260 210 70 160)
  days=(Mon Tue Wed Thu Fri Sat Sun)
  draw=()
  for i in "${!bars[@]}"; do
    x=$((80 + i * 105))
    draw+=(-fill '#3b6ea8' -draw "rectangle ${x},$((440 - bars[i])) $((x + 75)),440"
           -fill '#555' -pointsize 14 -annotate "+$((x + 22))+468" "${days[i]}")
  done
  convert -size 860x520 xc:'#fbfbfa' -font DejaVu-Sans \
    -fill '#222' -pointsize 26 -annotate +40+56 'Weekly builds' \
    -fill '#666' -pointsize 15 -annotate +40+84 'Successful builds per day' \
    -stroke '#ddd' -draw 'line 40,440 820,440' -draw 'line 40,340 820,340' \
    -draw 'line 40,240 820,240' -draw 'line 40,140 820,140' -stroke none \
    "${draw[@]}" -define png:color-type=6 "PNG32:${WORK}/sample.png"
fi

# The app's window with that title, x y width height: the GNUstep client window, not the window
# manager's frame, which GNOME Shell gives the same title (and an invisible shadow border).
client_window() {
  local name="$1" w
  for w in $(xdotool search --onlyvisible --name "${name}" 2>/dev/null); do
    xprop -id "${w}" WM_CLASS 2>/dev/null | grep -q '"ScreenshotTool"' || continue
    local info
    info="$(xwininfo -id "${w}" 2>/dev/null)" || continue
    local width height
    width="$(awk '/Width:/ {print $2}' <<<"${info}")"
    height="$(awk '/Height:/ {print $2}' <<<"${info}")"
    if (( width >= 400 && height >= 300 )); then
      echo "${w} $(awk '/Absolute upper-left X:/ {print $4}' <<<"${info}") $(awk '/Absolute upper-left Y:/ {print $4}' <<<"${info}") ${width} ${height}"
      return 0
    fi
  done
  return 1
}

client_geometry() {
  local id x y w h
  read -r id x y w h < <(client_window "$1") || return 1
  echo "${x} ${y} ${w} ${h}"
}

wait_for_window() {
  local name="$1"
  for _ in $(seq 1 40); do
    client_geometry "${name}" >/dev/null && return 0
    sleep 0.5
  done
  return 1
}

# shoot <name> <window title>: the whole screen, and the window with that title cropped out of it.
shoot() {
  local name="$1" title="$2" id x y w h extents left=0 right=0 top=0 bottom=0
  import -window root "${OUT_DIR}/${name}.png"
  echo "screenshots: ${OUT_DIR}/${name}.png"
  read -r id x y w h < <(client_window "${title}") || return 0
  # The window manager's decorations around the client window (its title bar), if it draws any.
  extents="$(xprop -id "${id}" _NET_FRAME_EXTENTS 2>/dev/null | sed -n 's/.*= //p')"
  [[ -n "${extents}" ]] && IFS=', ' read -r left right top bottom <<<"${extents}"
  # A theme that draws its own shadow (Adwaita) marks it with _GTK_FRAME_EXTENTS: leave it out, and
  # make the window's rounded corners transparent instead of the desktop behind them.
  local shadow sl=0 sr=0 st=0 sb=0
  shadow="$(xprop -id "${id}" _GTK_FRAME_EXTENTS 2>/dev/null | sed -n 's/.*= //p')"
  [[ -n "${shadow}" ]] && IFS=', ' read -r sl sr st sb <<<"${shadow}"
  convert "${OUT_DIR}/${name}.png" \
    -crop "$((w + left + right - sl - sr))x$((h + top + bottom - st - sb))+$((x - left + sl))+$((y - top + st))" \
    +repage "${OUT_DIR}/${name}-window.png"
  if [[ -n "${shadow}" ]]; then
    round_corners "${OUT_DIR}/${name}-window.png" "${CORNER_RADIUS:-12}"
  fi
  echo "screenshots: ${OUT_DIR}/${name}-window.png"
}

# round_corners <png> <radius>: makes the area outside rounded corners of that radius transparent.
round_corners() {
  local file="$1" r="$2"
  convert "${file}" -alpha set \
    \( +clone -alpha extract \
       -draw "fill black polygon 0,0 0,${r} ${r},0 fill white circle ${r},${r} ${r},0" \
       \( +clone -flip \) -compose Multiply -composite \
       \( +clone -flop \) -compose Multiply -composite \) \
    -alpha off -compose CopyOpacity -composite "${file}"
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
    # The theme, with its header bar (GNUstep draws the title bar), as GNOME users run it. Under
    # Adwaita the menus go in the header bar's primary menu, with no menu bar row.
    menu_style=""
    [[ "${label}" == "adwaita" ]] && menu_style='  GnomeThemeMenuStyle = primary;\n'
    printf "{\n  GSTheme = \"%s\";\n  GSX11HandlesWindowDecorations = NO;\n${menu_style}}\n" "${theme}" >"${DEFAULTS}/NSGlobalDomain.plist"
  fi
  LOG="${WORK}/app-${label}.log"

  # 1. No image: the empty state.
  launch "${LOG}"
  wait_for_window "ScreenshotTool" || { echo "screenshots: ${theme}: the window didn't appear" >&2; continue; }
  sleep 2
  shoot "${label}-empty" "ScreenshotTool"

  # 2. Preferences (the command key is Ctrl under Adwaita, Alt with GNUstep's defaults).
  xdotool key ctrl+comma; sleep 1.5
  xdotool search --onlyvisible --name "^Preferences$" >/dev/null 2>&1 || { xdotool key alt+comma; sleep 1.5; }
  # Drawing a new window under a theme can take several seconds on a virtual display.
  sleep 6
  shoot "${label}-preferences" "^Preferences$"

  # 3. An image.
  launch "${LOG}" "${WORK}/sample.png"
  wait_for_window "sample.png" || { echo "screenshots: ${theme}: the image window didn't appear" >&2; continue; }
  sleep 2
  shoot "${label}-image" "sample.png"
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
  shoot "${label}-text-toolbar" "sample.png"

  # 5. The tool settings popover, from the colour control, in a fresh window. The control is found
  #    by its swatch (the highlighter's yellow) in the window's top rows, wherever the theme and
  #    the toolbar's other items put it.
  launch "${LOG}" "${WORK}/sample.png"
  wait_for_window "sample.png" || { echo "screenshots: ${theme}: the image window didn't appear" >&2; continue; }
  sleep 2
  read -r X Y W H < <(client_geometry "sample.png")
  before="$(grep -c 'popover show invoked' "${LOG}" 2>/dev/null || true)"
  # The highlighter (H), so the swatch is its yellow whatever the last tool was.
  xdotool search --onlyvisible --name "sample.png" windowactivate --sync >/dev/null 2>&1; xdotool key h; sleep 0.5
  read -r SX SY < <(import -window root png:- 2>/dev/null | convert png:- -crop "${W}x120+${X}+${Y}" +repage txt:- \
    | awk -F'[ ,:]+' '/#FFFF00/ { print $1, $2; exit }')
  xdotool mousemove $((X + ${SX:-316} + 6)) $((Y + ${SY:-22} + 6)) click 1; sleep 1.5
  if [[ "$(grep -c 'popover show invoked' "${LOG}" 2>/dev/null || true)" == "${before}" ]]; then
    # Under GNUstep's default theme with window manager decorations, #60 clips the toolbar.
    echo "screenshots: ${theme}: the tool popover didn't open" >&2
  fi
  shoot "${label}-popover" "sample.png"
  stop_app
done
