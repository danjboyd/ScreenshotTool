#!/usr/bin/env bash
#
# gnome-launch-screenshottool.sh
# Copyright (C) 2025 Daniel Boyd
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301 USA.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="$(realpath "$SCRIPT_DIR/../ScreenshotTool.app")"
GNUSTEP_SH="${GNUSTEP_SH:-/usr/GNUstep/System/Library/Makefiles/GNUstep.sh}"

if [[ ! -x "$APP_BUNDLE/ScreenshotTool" ]]; then
  echo "Error: ScreenshotTool binary not found at $APP_BUNDLE/ScreenshotTool" >&2
  exit 1
fi

if [[ ! -f "$GNUSTEP_SH" ]]; then
  echo "Error: GNUstep env not found at $GNUSTEP_SH" >&2
  exit 1
fi

startup_token=""
portal_token=""
if command -v gdbus >/dev/null 2>&1; then
  portal_raw="$(gdbus call --session \
      --dest org.freedesktop.portal.Desktop \
      --object-path /org/freedesktop/portal/desktop \
      --method org.freedesktop.portal.ActivationToken.GetActivationToken \
      "ScreenshotTool.desktop" "" "" 2>/dev/null || true)"
  portal_token="$(printf '%s\n' "$portal_raw" | sed -n "s/.*'\(.*\)'.*/\1/p")"
  if [[ -z "$portal_token" ]]; then
    raw_id="$(gdbus call --session \
        --dest org.gnome.Shell \
        --object-path /org/gnome/Shell \
        --method org.gnome.Shell.GetStartupId 2>/dev/null || true)"
    portal_token="$(printf '%s\n' "$raw_id" | sed -n "s/.*'\(.*\)'.*/\1/p")"
  fi
  if [[ -n "$portal_token" ]]; then
    startup_token="$portal_token"
    export DESKTOP_STARTUP_ID="$portal_token"
    export XDG_ACTIVATION_TOKEN="$portal_token"
  fi
fi

set +u
# shellcheck disable=SC1090
source "$GNUSTEP_SH"
set -u

# Launch and try to raise the window once it appears (GNOME Wayland/Xwayland often ignores focus without an activation hint).
# Try to launch and raise the window explicitly; Wayland/XWayland may ignore activation tokens.
/usr/GNUstep/System/Tools/openapp "$APP_BUNDLE" "$@" &
app_pid=$!

if command -v wmctrl >/dev/null 2>&1 || command -v xdotool >/dev/null 2>&1; then
  latest_wid=""
  for _ in $(seq 1 120); do
    wid=""
    if command -v xdotool >/dev/null 2>&1; then
      wid="$(xdotool search --onlyvisible --name 'ScreenshotTool' 2>/dev/null | tail -n1 || true)"
      if [[ -z "$wid" ]]; then
        wid="$(xdotool search --onlyvisible --class 'ScreenshotTool' 2>/dev/null | tail -n1 || true)"
      fi
    fi
    if [[ -z "$wid" ]]; then
      if command -v wmctrl >/dev/null 2>&1; then
        wid="$(wmctrl -l | awk '/ScreenshotTool/ {w=$1} END{print w}')"
        if [[ -z "$wid" ]]; then
          wid="$(wmctrl -lx | awk '/[sS]creenshot[Tt]ool/ {w=$1} END{print w}')"
        fi
      fi
    fi
    if [[ -n "$wid" ]]; then
      latest_wid="$wid"
      if command -v wmctrl >/dev/null 2>&1; then wmctrl -ia "$wid" >/dev/null 2>&1 || true; fi
      if command -v xdotool >/dev/null 2>&1; then
        xdotool windowactivate --sync "$wid" >/dev/null 2>&1 || true
        xdotool windowraise "$wid" >/dev/null 2>&1 || true
      fi
      break
    fi
    sleep 0.1
  done
  if [[ -n "$latest_wid" ]]; then
    if command -v wmctrl >/dev/null 2>&1; then wmctrl -ia "$latest_wid" >/dev/null 2>&1 || true; fi
    if command -v xdotool >/dev/null 2>&1; then
      xdotool windowactivate --sync "$latest_wid" >/dev/null 2>&1 || true
      xdotool windowraise "$latest_wid" >/dev/null 2>&1 || true
    fi
  fi
fi

wait "$app_pid"
exit $?
