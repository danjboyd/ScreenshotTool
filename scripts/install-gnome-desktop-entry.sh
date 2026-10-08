#!/usr/bin/env bash
#
# install-gnome-desktop-entry.sh
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

# Install a GNOME desktop entry for ScreenshotTool that works with startup
# notifications so the first window receives focus.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="$(realpath "$SCRIPT_DIR/../ScreenshotTool.app")"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_FILE="$DESKTOP_DIR/screenshottool.desktop"
ICON_FILE="$(realpath "$SCRIPT_DIR/../Resources/ScreenshotToolIcon.png")"
LAUNCHER_SCRIPT="$(realpath "$SCRIPT_DIR/gnome-launch-screenshottool.sh")"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: ScreenshotTool.app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

if [[ ! -f "$ICON_FILE" ]]; then
  echo "Error: Application icon not found at $ICON_FILE" >&2
  exit 1
fi

mkdir -p "$DESKTOP_DIR"

cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=ScreenshotTool
Comment=Annotate screenshots with pen, highlighter, and text overlays
Exec=$LAUNCHER_SCRIPT %U
Icon=$ICON_FILE
Terminal=false
StartupNotify=false
StartupWMClass=ScreenshotTool
Categories=Graphics;Utility;
MimeType=image/png;image/jpeg;image/jpg;image/webp;image/tiff;
Actions=take-screenshot;

[Desktop Action take-screenshot]
Name=Take Screenshot
Exec=$LAUNCHER_SCRIPT --capture
EOF

chmod 644 "$DESKTOP_FILE"

echo "Installed desktop entry at $DESKTOP_FILE"
echo "Launch with: gtk-launch screenshottool"
