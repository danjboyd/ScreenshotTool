#!/usr/bin/env bash
# Checks that the AppImage's windows close, rather than the app being killed, when a GNOME window
# manager is asked to close them (Alt+F4, the Overview's close button, Close in the dock).
#
# Under GNOME the AppImage uses the Adwaita theme, which draws its own window decorations. Its
# windows must list WM_DELETE_WINDOW in WM_PROTOCOLS: without it, Mutter has no way to ask the app
# to close a window and kills the whole client with XKillClient ("X connection to :N broken").
# libs-back 0.32.0 lists it only on windows the window manager decorates; the toolchain carries
# scripts/patches/libs-back-0.32-wm-delete-window.patch for that.
#
# Usage: Tools/check_wm_close.sh <ScreenshotTool.AppImage>
#
# Runs on a private Xvfb display with its own window manager, D-Bus session, XDG directories and
# GNUstep defaults, so it doesn't touch the desktop or your settings.
#   CHECK_WM   gnome-shell or mutter (default: gnome-shell if installed, else mutter)
#   KEEP_WORK  set to keep the work directory (logs, the extracted AppImage)
# Needs Xvfb, xdotool, xprop (x11-utils), dbus-run-session, and GNOME Shell or Mutter.

set -uo pipefail

APPIMAGE="$(realpath "${1:?usage: Tools/check_wm_close.sh <ScreenshotTool.AppImage>}")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-wm-close.XXXXXX")"
PIDS=()
APP_PID=""
FAILURES=0

for tool in Xvfb xdotool xprop dbus-run-session; do
  command -v "${tool}" >/dev/null || { echo "check_wm_close: ${tool} is needed" >&2; exit 2; }
done
WM="${CHECK_WM:-}"
if [[ -z "${WM}" ]]; then
  if command -v gnome-shell >/dev/null; then WM=gnome-shell
  elif command -v mutter >/dev/null; then WM=mutter
  else echo "check_wm_close: GNOME Shell or Mutter is needed" >&2; exit 2
  fi
fi

cleanup() {
  [[ -n "${APP_PID}" ]] && kill -KILL "${APP_PID}" 2>/dev/null
  for pid in "${PIDS[@]}"; do kill "${pid}" 2>/dev/null; done
  # dbus-run-session leaves the session's daemons running: stop those of this run.
  for pid in $(pgrep -u "$(id -u)" 2>/dev/null); do
    { tr '\0' '\n' <"/proc/${pid}/environ"; } 2>/dev/null | grep -qxF "XDG_RUNTIME_DIR=${WORK}/run" && kill "${pid}" 2>/dev/null
  done
  if [[ -n "${KEEP_WORK:-}" ]]; then echo "check_wm_close: kept ${WORK}"; else rm -rf "${WORK}"; fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { echo "ok: $*"; }

# The AppImage, extracted so its GNOME configuration can be pointed at private defaults. AppRun
# sets GNUSTEP_CONFIG_FILE itself, and GNUstep finds the user's home without $HOME, so this is the
# way to keep the run off ~/GNUstep/Defaults.
(cd "${WORK}" && "${APPIMAGE}" --appimage-extract >/dev/null) || { echo "check_wm_close: can't extract ${APPIMAGE}" >&2; exit 2; }
ROOT="${WORK}/squashfs-root"
CONF="${ROOT}/usr/runtime/etc/GNUstep-default-theme/GNUstep.conf"
[[ -f "${CONF}" ]] || { echo "check_wm_close: no GNOME configuration in the AppImage (${CONF})" >&2; exit 2; }
mkdir -p "${WORK}"/{config,data,cache,state,run,defaults,library}
chmod 700 "${WORK}/run"
sed -i -e "s#^GNUSTEP_USER_DEFAULTS_DIR=.*#GNUSTEP_USER_DEFAULTS_DIR=${WORK}/defaults#" \
       -e "s#^GNUSTEP_USER_DIR_LIBRARY=.*#GNUSTEP_USER_DIR_LIBRARY=${WORK}/library#" "${CONF}"
chmod 600 "${CONF}"

for n in $(seq 140 170); do
  [[ ! -e "/tmp/.X11-unix/X${n}" && ! -e "/tmp/.X${n}-lock" ]] && break
done
export DISPLAY=":${n}"
unset WAYLAND_DISPLAY
Xvfb "${DISPLAY}" -screen 0 1600x1000x24 -nolisten tcp +extension GLX +extension RANDR >/dev/null 2>&1 &
PIDS+=($!)
sleep 1.5

SESSION_ENV=(HOME="${HOME}" PATH="${PATH}" DISPLAY="${DISPLAY}" XDG_CONFIG_HOME="${WORK}/config"
  XDG_DATA_HOME="${WORK}/data" XDG_CACHE_HOME="${WORK}/cache" XDG_STATE_HOME="${WORK}/state"
  XDG_RUNTIME_DIR="${WORK}/run" GSETTINGS_BACKEND=keyfile LIBGL_ALWAYS_SOFTWARE=1
  GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix XDG_CURRENT_DESKTOP=GNOME)
case "${WM}" in
  gnome-shell) WM_COMMAND='exec gnome-shell --x11' ;;
  mutter) WM_COMMAND='exec mutter --x11' ;;
  *) echo "check_wm_close: CHECK_WM must be gnome-shell or mutter" >&2; exit 2 ;;
esac
env -i "${SESSION_ENV[@]}" dbus-run-session -- sh -c \
  "echo \"\${DBUS_SESSION_BUS_ADDRESS}\" >\"\${XDG_RUNTIME_DIR}/bus-address\"; ${WM_COMMAND}" \
  >"${WORK}/wm.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 60); do
  xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id" && break
  sleep 0.5
done
xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id" \
  || { echo "check_wm_close: ${WM} didn't start"; tail -20 "${WORK}/wm.log"; exit 2; }
BUS="$(cat "${WORK}/run/bus-address" 2>/dev/null)"
# GNOME Shell starts in the overview: leave it once the shell says it's up.
if [[ "${WM}" == "gnome-shell" ]] && command -v gdbus >/dev/null; then
  for _ in $(seq 1 60); do
    reply="$(DBUS_SESSION_BUS_ADDRESS="${BUS}" gdbus call --session --dest org.gnome.Shell \
      --object-path /org/gnome/Shell --method org.freedesktop.DBus.Properties.Get \
      org.gnome.Shell OverviewActive 2>/dev/null)"
    [[ "${reply}" == *false* ]] && break
    xdotool key Escape; sleep 1
  done
fi
echo "check_wm_close: ${WM} on ${DISPLAY}"

# Mapped top-level windows of the app, from the window manager's client list.
app_windows() {
  local w
  for w in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*'); do
    xprop -id "${w}" WM_CLASS 2>/dev/null | grep -q '"ScreenshotTool"' && echo "$((w))"
  done
}
window_name() { xprop -id "$1" WM_NAME 2>/dev/null | cut -d= -f2- | sed 's/^ *//'; }
alive() { kill -0 "${APP_PID}" 2>/dev/null; }
wait_for() {  # wait_for SECONDS COMMAND...: until COMMAND succeeds
  local i
  for i in $(seq 1 $(($1 * 2))); do "${@:2}" && return 0; sleep 0.5; done
  return 1
}
has_window() { app_windows | grep -qx "$1"; }
lacks_window() { ! has_window "$1"; }
has_second_window() { [[ -n "$(app_windows | grep -vx "${MAIN}")" ]]; }
focus() { xdotool windowactivate --sync "$1" >/dev/null 2>&1 || xdotool windowfocus --sync "$1"; sleep 0.5; }

check_protocols() {
  local w protocols
  protocols="$(xprop -id "$1" WM_PROTOCOLS 2>/dev/null)"
  if [[ "${protocols}" == *WM_DELETE_WINDOW* ]]; then
    pass "$2 lists WM_DELETE_WINDOW"
  else
    fail "$2 doesn't list WM_DELETE_WINDOW (${protocols#*=})"
  fi
}

# The app's exit: alive, or exited by itself with status 0. Killed by the window manager, its
# X connection breaks and it exits with status 1, saying so on stderr.
check_not_killed() {
  if grep -q 'X connection to .* broken' "${WORK}/app.out"; then
    fail "$1: the window manager killed the app (X connection broken)"
  elif alive; then
    pass "$1: the app is still running"
  else
    local status=0
    wait "${APP_PID}" || status=$?
    if [[ "${status}" -eq 0 ]]; then pass "$1: the app quit cleanly"; else fail "$1: the app exited with status ${status}"; fi
    APP_PID=""
  fi
}

# The AppImage's AppRun, as the desktop launches it under GNOME.
env -i "${SESSION_ENV[@]}" DBUS_SESSION_BUS_ADDRESS="${BUS}" \
  SCREENSHOT_TOOL_LOG_PATH="${WORK}/app.log" "${ROOT}/AppRun" >"${WORK}/app.out" 2>&1 &
APP_PID=$!
if ! wait_for 30 eval '[[ -n "$(app_windows)" ]]'; then
  echo "check_wm_close: the app showed no window"; tail -20 "${WORK}/app.out"; exit 1
fi
sleep 2
MAIN="$(app_windows | head -1)"
check_protocols "${MAIN}" "the main window ($(window_name "${MAIN}"))"

# Preferences: Alt+F4 closes it, and only it.
focus "${MAIN}"
xdotool key --clearmodifiers ctrl+comma
if wait_for 10 has_second_window; then
  PREFS="$(app_windows | grep -vx "${MAIN}" | head -1)"
  check_protocols "${PREFS}" "the Preferences window ($(window_name "${PREFS}"))"
  focus "${PREFS}"
  xdotool key --clearmodifiers alt+F4
  wait_for 10 lacks_window "${PREFS}" || fail "Alt+F4 left Preferences open"
  sleep 1
  check_not_killed "Alt+F4 on Preferences"
  if alive && has_window "${MAIN}"; then pass "the main window is still open"
  elif alive; then fail "the main window closed with Preferences"
  fi
else
  fail "Ctrl+, opened no Preferences window"
fi

# The main window: Alt+F4 closes it (the app has no unsaved changes, so it doesn't ask).
if alive; then
  focus "${MAIN}"
  xdotool key --clearmodifiers alt+F4
  wait_for 10 eval 'lacks_window "${MAIN}" || ! alive' || fail "Alt+F4 left the main window open"
  sleep 1
  check_not_killed "Alt+F4 on the main window"
fi

if [[ "${FAILURES}" -gt 0 ]]; then
  echo "check_wm_close: ${FAILURES} check(s) failed. App output:"
  tail -20 "${WORK}/app.out"
  exit 1
fi
echo "check_wm_close: passed"
