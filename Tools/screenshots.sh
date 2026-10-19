#!/usr/bin/env bash
# Screenshot ScreenshotTool's main screens under GNUstep's default theme and the Adwaita theme, on a
# private X display, for reviewing how each theme presents the app (#75).
#
# Usage: Tools/screenshots.sh [output-dir]          (default: screenshots/)
#   THEMES="default Adwaita"   the themes to use; "default" is GNUstep's own
#   SCREENSHOT_LIBRARY_DIR     a GNUstep Library folder holding Themes/ (default: the user's)
#   SCREENSHOT_WM              gnome-shell, openbox or none (default: the first one installed)
#   SCREENSHOT_SAMPLE          the image to open (default: Tools/screenshot-sample/security-settings.png,
#                              marked up as the README shows it; another image isn't marked up)
#   SCREENSHOT_SAMPLE_DIR      the folder the sample is opened from, which a title bar shows
#                              (default: the work folder; ~/Pictures in a throwaway account reads well)
#   KEEP_WORK=1                keep the work folder (app logs, generated configuration)
#   SCREENSHOT_APP             the program to run (default: the built app), such as a script that
#                              runs a release build's binary with its runtime: its GNUstep backend
#                              may carry patches this machine's doesn't (#60)
#   SCREENSHOT_APP_EXE         that program's executable, if the script execs another (to stop it)
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
APP="${SCREENSHOT_APP:-${ROOT_DIR}/ScreenshotTool.app/ScreenshotTool}"
APP_EXE="${SCREENSHOT_APP_EXE:-${APP}}"
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
    [[ "$(readlink "/proc/${pid}/exe" 2>/dev/null)" == "$(realpath "${APP_EXE}")" ]] && kill -KILL "${pid}" 2>/dev/null
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
  # A fresh session is a first login: GNOME Shell 48 would open its welcome dialog over the app.
  mkdir -p "${WORK}/config/glib-2.0/settings"
  printf '[org/gnome/shell]\nwelcome-dialog-last-shown-version=%s\n' "'999'" >"${WORK}/config/glib-2.0/settings/keyfile"
  env -i HOME="${HOME}" PATH="${PATH}" DISPLAY="${DISPLAY}" XDG_CONFIG_HOME="${WORK}/config" \
    XDG_DATA_HOME="${WORK}/data" XDG_CACHE_HOME="${WORK}/cache" XDG_STATE_HOME="${WORK}/state" \
    XDG_RUNTIME_DIR="${WORK}/run" GSETTINGS_BACKEND=keyfile LIBGL_ALWAYS_SOFTWARE=1 \
    GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix \
    dbus-run-session -- sh -c 'echo "${DBUS_SESSION_BUS_ADDRESS}" >"${XDG_RUNTIME_DIR}/bus-address"; exec gnome-shell --x11' \
    >"${WORK}/wm.log" 2>&1 &
  PIDS+=($!)
  for _ in $(seq 1 60); do
    xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id" && break
    sleep 0.5
  done
  # GNOME Shell starts in the overview: leave it. Escape works only once the shell has finished
  # starting, which takes much longer on a loaded machine, so ask the shell (its OverviewActive
  # property, on its session bus) rather than wait a fixed time.
  # Succeeds while the overview is up, or while the shell can't answer yet.
  overview_active() {
    local address reply
    address="$(cat "${WORK}/run/bus-address" 2>/dev/null)"
    [[ -n "${address}" ]] || return 0
    reply="$(DBUS_SESSION_BUS_ADDRESS="${address}" gdbus call --session --dest org.gnome.Shell \
      --object-path /org/gnome/Shell --method org.freedesktop.DBus.Properties.Get \
      org.gnome.Shell OverviewActive 2>/dev/null)"
    [[ "${reply}" != *false* ]]
  }
  if command -v gdbus >/dev/null; then
    # The shell opens the overview a moment after it says it isn't in it: wait until the
    # overview has stayed closed for three seconds.
    closed=0
    for _ in $(seq 1 90); do
      if overview_active; then
        closed=0
        xdotool key Escape
      else
        closed=$((closed + 1))
        [[ "${closed}" -ge 3 ]] && break
      fi
      sleep 1
    done
    overview_active && echo "screenshots: GNOME Shell stayed in the overview" >&2
  else
    sleep 4
    xdotool key Escape; sleep 1; xdotool key Escape; sleep 1
  fi
  echo "screenshots: window manager GNOME Shell"
elif command -v openbox >/dev/null; then
  openbox >"${WORK}/wm.log" 2>&1 &
  PIDS+=($!)
  sleep 2
  echo "screenshots: window manager Openbox"
else
  echo "screenshots: no window manager (GNOME Shell or Openbox); windows have no title bars" >&2
fi

# The sample image, as sample.png, the title the script looks for: the README's shared one (a
# fictional settings page, the same on every platform's shots), or the one asked for.
SAMPLE="${SCREENSHOT_SAMPLE:-${ROOT_DIR}/Tools/screenshot-sample/security-settings.png}"
SAMPLE_DIR="${SCREENSHOT_SAMPLE_DIR:-${WORK}}"
mkdir -p "${SAMPLE_DIR}"
convert "${SAMPLE}" -define png:color-type=6 "PNG32:${SAMPLE_DIR}/sample.png"
MARKUP=0
[[ "$(realpath "${SAMPLE}")" == "$(realpath "${ROOT_DIR}/Tools/screenshot-sample/security-settings.png")" ]] && MARKUP=1

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

# menu_window: GNUstep's main menu when it's a window of its own (its NeXTSTEP-style menus, under
# its default theme), id x y width height: a narrow column of the app's that isn't its main window.
menu_window() {
  [[ "${MENU_STYLE:-}" == "nextstep" ]] || return 1
  local w info width height
  for w in $(xdotool search --onlyvisible --classname ScreenshotTool 2>/dev/null); do
    info="$(xwininfo -id "${w}" 2>/dev/null)" || continue
    width="$(awk '/Width:/ {print $2}' <<<"${info}")"
    height="$(awk '/Height:/ {print $2}' <<<"${info}")"
    (( width >= 60 && width <= 300 && height >= 40 && height <= 400 )) || continue
    xwininfo -id "${w}" -all 2>/dev/null | grep -q 'Override Redirect State: no' || continue
    echo "${w} $(awk '/Absolute upper-left X:/ {print $4}' <<<"${info}") $(awk '/Absolute upper-left Y:/ {print $4}' <<<"${info}") ${width} ${height}"
    return 0
  done
  return 1
}

# place_menu: GNUstep opens its menu at the screen's top left, under GNOME Shell's top bar. The main
# window stays where the app put it (moving or resizing it under GNUstep's theme can clip it, #60):
# the menu goes beside it, level with its top, so the shot shows them together.
place_menu() {
  local mid mx my mw mh wid wx wy
  read -r mid mx my mw mh < <(menu_window) || return 0
  read -r wid wx wy _ < <(client_window "sample.png") || return 0
  local top
  top="$(xprop -id "${wid}" _NET_FRAME_EXTENTS 2>/dev/null | sed -n 's/.*= //p' | awk -F', ' '{print $3}')"
  xdotool windowmove "${mid}" $((wx - mw - 24)) $((wy - ${top:-0})); sleep 1
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
  # make the window's rounded corners transparent instead of the desktop behind them, from the
  # window's own alpha (window_alpha_edges).
  local shadow sl=0 sr=0 st=0 sb=0
  shadow="$(xprop -id "${id}" _GTK_FRAME_EXTENTS 2>/dev/null | sed -n 's/.*= //p')"
  [[ -n "${shadow}" ]] && IFS=', ' read -r sl sr st sb <<<"${shadow}"
  local fx=$((x - left + sl)) fy=$((y - top + st)) fw=$((w + left + right - sl - sr)) fh=$((h + top + bottom - st - sb))
  local mid mx my mw mh
  if read -r mid mx my mw mh < <(menu_window); then
    # GNUstep's own menu, in a window of its own: the shot is both windows, with nothing between.
    local bx=$((fx < mx ? fx : mx)) by=$((fy < my ? fy : my))
    local bw=$(( (fx + fw > mx + mw ? fx + fw : mx + mw) - bx )) bh=$(( (fy + fh > my + mh ? fy + fh : my + mh) - by ))
    read -r sw sh < <(identify -format '%w %h' "${OUT_DIR}/${name}.png")
    convert "${OUT_DIR}/${name}.png" \
      \( -size "${sw}x${sh}" xc:black -fill white \
         -draw "rectangle ${fx},${fy} $((fx + fw - 1)),$((fy + fh - 1))" \
         -draw "rectangle ${mx},${my} $((mx + mw - 1)),$((my + mh - 1))" \) \
      -alpha off -compose CopyOpacity -composite -crop "${bw}x${bh}+${bx}+${by}" +repage \
      "PNG32:${OUT_DIR}/${name}-window.png"
    echo "screenshots: ${OUT_DIR}/${name}-window.png"
    return 0
  fi
  convert "${OUT_DIR}/${name}.png" -crop "${fw}x${fh}+${fx}+${fy}" +repage "${OUT_DIR}/${name}-window.png"
  if [[ -n "${shadow}" ]]; then
    if window_alpha_edges "${OUT_DIR}/${name}-window.png" "${id}" "${sl}" "${sr}" "${st}" "${sb}"; then
      clip_corners "${OUT_DIR}/${name}-window.png" "${CORNER_RADIUS:-12}"
    else
      round_corners "${OUT_DIR}/${name}-window.png" "${CORNER_RADIUS:-12}"
    fi
  fi
  echo "screenshots: ${OUT_DIR}/${name}-window.png"
}

# window_alpha_edges <png> <window> <left> <right> <top> <bottom>: gives the cropped screen shot in
# <png> the window's own alpha at its edges. A theme that rounds its corners draws them into an
# ARGB window, antialiased against nothing; the screen shot has them over the desktop, which a
# mask of our own leaves as a dark fringe where its arc misses the theme's. Where the window is
# opaque the screen shot stays, popovers and all; elsewhere the window's own pixels, read with xwd
# and less its shadow (the _GTK_FRAME_EXTENTS insets), replace it. Fails, for round_corners to
# take over, when the window isn't 32-bit or its size doesn't match.
window_alpha_edges() {
  local file="$1" id="$2" raw="${WORK}/window-raw.png"
  [[ "$(xwininfo -id "${id}" 2>/dev/null | awk '/Depth:/ {print $2}')" == "32" ]] || return 1
  xwd -id "${id}" -silent >"${WORK}/window.xwd" 2>/dev/null || return 1
  python3 -I "${ROOT_DIR}/Tools/xwd_to_png.py" "${WORK}/window.xwd" "${raw}" "$3" "$4" "$5" "$6" || return 1
  if [[ "$(identify -format '%wx%h' "${raw}")" != "$(identify -format '%wx%h' "${file}")" ]]; then
    echo "screenshots: the window's own pixels are $(identify -format '%wx%h' "${raw}"), the crop $(identify -format '%wx%h' "${file}")" >&2
    return 1
  fi
  convert "${raw}" \( "${file}" -alpha off \( "${raw}" -alpha extract -threshold 99.9% \) \
            -compose CopyOpacity -composite \) -compose Over -composite "PNG32:${file}"
}

# clip_corners <png> <radius>: clears what's outside the window's rounded corners from the
# window's own pixels. The theme's shadow reaches into the corner squares, outside the curve, and
# would show there as a faint grey wedge on a light page. Each pixel keeps the lesser of its own
# alpha and a rounded rectangle's, so the theme's antialiased edge stays inside the curve.
clip_corners() {
  local file="$1" r="$2" w h
  read -r w h < <(identify -format '%w %h' "${file}")
  convert "${file}" \( +clone -alpha extract \
      \( -size "${w}x${h}" xc:black -fill white -draw "roundrectangle 0,0 $((w - 1)),$((h - 1)) ${r},${r}" \) \
      -compose Darken -composite \) \
    -alpha off -compose CopyOpacity -composite "PNG32:${file}"
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

# image_origin: where the image's pixel (0,0) is on screen, at 100%: found from the first pixel of
# the sample's logo colour, at (25,16) in the image.
image_origin() {
  local x y w h sx sy
  read -r x y w h < <(client_geometry "sample.png") || return 1
  read -r sx sy < <(import -window root png:- 2>/dev/null | convert png:- -crop "${w}x${h}+${x}+${y}" +repage txt:- \
    | awk -F'[ ,:]+' '/#5B5BD6/ { print $1, $2; exit }')
  [[ -n "${sx}" ]] || return 1
  echo "$((x + sx - 25)) $((y + sy - 16))"
}

# at <x> <y>: moves the pointer to that image pixel.
at() { xdotool mousemove $((OX + $1)) $((OY + $2)); }

# drag <x1> <y1> <x2> <y2>: a drag between image pixels, in steps, as a hand makes it.
drag() {
  local i
  at "$1" "$2"; sleep 0.2
  xdotool mousedown 1; sleep 0.1
  for i in $(seq 1 12); do
    at $(($1 + ($3 - $1) * i / 12)) $(($2 + ($4 - $2) * i / 12)); sleep 0.03
  done
  sleep 0.1; xdotool mouseup 1; sleep 0.4
}

# click_at <x> <y>: a click at an image pixel.
click_at() { at "$1" "$2"; sleep 0.2; xdotool mousedown 1; sleep 0.1; xdotool mouseup 1; sleep 0.4; }

# use_tool <key> <tool>: picks a tool by its shortcut, and checks the app's log that it took (a tool
# that was already active logs nothing, so it's only retried once).
use_tool() {
  local i _ lines
  for i in 1 2 3; do
    lines="$(wc -l <"${LOG}" 2>/dev/null || echo 0)"
    xdotool key "$1"
    for _ in $(seq 1 8); do
      tail -n "+$((lines + 1))" "${LOG}" 2>/dev/null | grep -q "active=com.screenshottool.toolbar.$2\$" && return 0
      sleep 0.25
    done
    tail -n 40 "${LOG}" 2>/dev/null | grep "active=com.screenshottool.toolbar." | tail -1 \
      | grep -q "toolbar.$2\$" && return 0
  done
  echo "screenshots: ${theme}: the $2 tool didn't take" >&2
  return 1
}

# The README's markup, in the sample's pixels (as on the Windows and macOS shots): the email
# address and API key redacted, steps 1 and 2, a highlight, and an arrow to the toggle. The text
# ("Turn this on") is added by the caller, which shoots it while it's being edited. Its box starts at
# (576,326), a little left of the Windows shot's, so DejaVu Sans Bold under GNUstep's default theme
# clears the arrow.
mark_up() {
  # The canvas takes the tool shortcuts only once the image has been clicked (under GNUstep's default
  # theme, not before): a click where the email address is redacted next, which covers it.
  click_at 450 164
  use_tool x redact
  drag 354 151 548 177
  drag 354 263 568 289
  use_tool h highlighter
  drag 242 349 530 349
  use_tool n step
  click_at 158 147
  click_at 212 327
  use_tool a arrow
  drag 680 337 764 337
}

launch() {
  local log="$1"; shift
  stop_app
  # No custom actions: the user's own would show on the toolbar.
  mkdir -p "${WORK}/actions"
  GNUSTEP_CONFIG_FILE="${CONFIG}" WAYLAND_DISPLAY= XDG_SESSION_TYPE=x11 SCREENSHOT_TOOL_LOG_PATH="${log}" \
    SCREENSHOT_TOOL_ACTIONS_DIR="${WORK}/actions" "${APP}" "$@" >/dev/null 2>&1 &
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
  # The defaults the release AppImage ships (packaging/package.manifest.json), so the shots show
  # what users get: its global defaults, and for its default theme (Adwaita on GNOME) that theme's
  # own, such as its header bar. Another theme gets the header bar too, as before.
  python3 -I - "${ROOT_DIR}/packaging/package.manifest.json" "${theme}" >"${DEFAULTS}/NSGlobalDomain.plist" <<'EOF_DEFAULTS'
import json, sys
config = json.load(open(sys.argv[1]))["backends"]["appimage"].get("gnustepConfig", {})
theme = sys.argv[2]
values = dict(config.get("globalDefaults", {}))
default_theme = config.get("defaultTheme", {})
if theme == default_theme.get("name"):
    values.update(default_theme.get("defaults", {}))
    values["GSTheme"] = theme
elif theme != "default":
    values.update({"GSTheme": theme, "GSX11HandlesWindowDecorations": False})
else:
    # GNUstep's own menus, a column of their own, as its theme is best known for.
    values["NSMenuInterfaceStyle"] = "NSNextStepInterfaceStyle"
def literal(value):
    if isinstance(value, bool):
        return "YES" if value else "NO"
    if isinstance(value, (int, float)):
        return str(value)
    return '"%s"' % str(value).replace("\\", "\\\\").replace('"', '\\"')
print("{")
for key in sorted(values):
    print('  "%s" = %s;' % (key, literal(values[key])))
print("}")
EOF_DEFAULTS
  LOG="${WORK}/app-${label}.log"
  MENU_STYLE=""
  [[ "${theme}" == "default" ]] && MENU_STYLE=nextstep

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
  launch "${LOG}" "${SAMPLE_DIR}/sample.png"
  wait_for_window "sample.png" || { echo "screenshots: ${theme}: the image window didn't appear" >&2; continue; }
  sleep 2
  shoot "${label}-image" "sample.png"
  # Wide enough for the whole header bar, Share included, as on a desktop with room for it. Not
  # under GNUstep's theme, which opens wide enough for its toolbar, and whose window an xdotool
  # resize leaves undrawn (#60).
  read -r WID X Y W H < <(client_window "sample.png")
  if [[ "${MENU_STYLE}" == "nextstep" ]]; then
    place_menu
  elif [[ -n "${WID:-}" ]] && (( W < ${SHOT_WIDTH:-1300} )); then
    xdotool windowsize "${WID}" "${SHOT_WIDTH:-1300}" "${H}"; sleep 2
  fi
  read -r X Y W H < <(client_geometry "sample.png")

  # 4. The text toolbar, while a text annotation is being written. On the README's sample, it's the
  #    README's markup with "Turn this on" (bold) left of the arrow; on another image, "Annotation".
  #    The window is focused through its status bar: a click on the canvas would draw.
  xdotool search --onlyvisible --name "sample.png" windowactivate --sync >/dev/null 2>&1; sleep 0.5
  xdotool mousemove $((X + W / 2)) $((Y + H - 6)) click 1; sleep 0.5
  if [[ "${MARKUP}" == 1 ]]; then
    xdotool key ctrl+1; sleep 1
    if read -r OX OY < <(image_origin); then
      mark_up
    else
      echo "screenshots: ${theme}: the sample's logo isn't on screen; no markup" >&2
      MARKUP=0
    fi
  fi
  xdotool key t
  for _ in $(seq 1 20); do
    tail -n 30 "${LOG}" 2>/dev/null | grep -q 'active=com.screenshottool.toolbar.text' && break
    sleep 0.25
  done
  sleep 0.5
  if [[ "${MARKUP}" == 1 ]]; then
    click_at 576 326
  else
    xdotool mousemove $((X + W / 3)) $((Y + H / 2)) click 1
  fi
  for _ in $(seq 1 20); do
    tail -n 30 "${LOG}" 2>/dev/null | grep -q 'showHUDMessage' && break
    sleep 0.25
  done
  # The text bar can take a few seconds to lay out.
  sleep 3
  if [[ "${MARKUP}" == 1 ]]; then
    xdotool type --delay 80 "Turn this on"; sleep 0.5
    xdotool key ctrl+b; sleep 1
  else
    xdotool type --delay 80 "Annotation"; sleep 1
  fi
  # The text row scrolls the canvas so the image stays put on screen, covering its top: scroll
  # back to the top (wheel up, over the canvas) so the shot shows the whole image.
  xdotool mousemove $((X + W / 2)) $((Y + H * 3 / 4)) click --repeat 5 --delay 100 4; sleep 1
  shoot "${label}-text-toolbar" "sample.png"

  # 5. The tool settings popover, from the colour control. On the README's sample it's over the
  #    finished markup; on another image, in a fresh window. The control is found by its swatch (the
  #    highlighter's yellow) in the window's top rows, wherever the theme and the toolbar's other
  #    items put it.
  if [[ "${MARKUP}" == 1 ]]; then
    xdotool key Escape; sleep 1
  else
    launch "${LOG}" "${SAMPLE_DIR}/sample.png"
    wait_for_window "sample.png" || { echo "screenshots: ${theme}: the image window didn't appear" >&2; continue; }
    sleep 2
  fi
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
