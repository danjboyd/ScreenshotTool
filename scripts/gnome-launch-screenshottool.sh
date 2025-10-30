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
APP_BINARY="$APP_BUNDLE/ScreenshotTool"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Error: ScreenshotTool binary not found at $APP_BINARY" >&2
  exit 1
fi

if [[ -z "${DESKTOP_STARTUP_ID:-}" ]] && command -v gdbus >/dev/null; then
  raw_id="$(gdbus call --session \
      --dest org.gnome.Shell \
      --object-path /org/gnome/Shell \
      --method org.gnome.Shell.GetStartupId 2>/dev/null || true)"
  if [[ -n "$raw_id" ]]; then
    DESKTOP_STARTUP_ID="$(printf '%s\n' "$raw_id" | sed -n "s/.*'\(.*\)'.*/\1/p")"
    export DESKTOP_STARTUP_ID
  fi
fi

export OPEN_STEP_ROOT="${OPEN_STEP_ROOT:-/usr/GNUstep}" || true
exec "$APP_BINARY" "$@"
