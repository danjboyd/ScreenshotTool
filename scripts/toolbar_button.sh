#!/usr/bin/env bash
#
# toolbar_button.sh
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

# toolbar_button.sh MODE IN_GLYPH.png OUT.png
# MODE = normal | pressed
set -euo pipefail
MODE="${1:-pressed}"
IN="${2:-glyph.png}"
OUT="${3:-out.png}"

IM_TOOL="$(command -v magick || command -v convert || true)"
if [[ -z "$IM_TOOL" ]]; then
  echo "ImageMagick (magick/convert) not found in PATH." >&2
  exit 1
fi

# ---- Tunables for a light GNOME-like headerbar ----
SIZE=32
RADIUS=6
ICON=24          # unused (kept for compatibility)
NUDGE_Y=0
BG_NORMAL="#E9ECF2"
BG_PRESSED="#D6D8DC"
STROKE_OUT="#5B626E"
HILITE="#FFFFFF"   # top/left inner hilite
SHADE="#000000"    # bottom/right inner shadow
GLYPH_DARKEN=100   # overridden below for pressed

if [[ "$MODE" == "pressed" ]]; then
  BG="$BG_PRESSED"
  GLYPH_DARKEN=92
  NUDGE_Y=1
else
  BG="$BG_NORMAL"
  GLYPH_DARKEN=100
  NUDGE_Y=0
fi

SIZE=$(identify -format '%w' "$IN")
if [[ -z "$SIZE" || "$SIZE" -le 0 ]]; then
  SIZE=32
fi

BORDER=$((SIZE / 32))
if ((BORDER < 1)); then BORDER=1; fi
RADIUS=$((SIZE * 6 / 32))
if ((RADIUS < BORDER)); then RADIUS=BORDER; fi

tmp_icon=$(mktemp /tmp/toolbar-iconXXXXXX.png)
if [[ "$MODE" == "pressed" ]]; then
  "${IM_TOOL}" "$IN" -alpha on -modulate ${GLYPH_DARKEN},100,100 "$tmp_icon"
else
  cp "$IN" "$tmp_icon"
fi

overlay=$(mktemp /tmp/toolbar-overlayXXXXXX.png)
hilite=$(mktemp /tmp/toolbar-hiliteXXXXXX.png)
shade=$(mktemp /tmp/toolbar-shadeXXXXXX.png)

"${IM_TOOL}" -size ${SIZE}x${SIZE} xc:none \
  -stroke "$STROKE_OUT" -strokewidth $BORDER -fill none \
  -draw "roundrectangle $((BORDER/2)),$((BORDER/2)) $((SIZE-1-BORDER/2)),$((SIZE-1-BORDER/2)) ${RADIUS},${RADIUS}" \
  "$overlay"

"${IM_TOOL}" -size ${SIZE}x${SIZE} xc:none \
  -stroke "$HILITE" -strokewidth $BORDER -fill none \
  -draw "line $BORDER,$BORDER $((SIZE-1-BORDER)),$BORDER" \
  -draw "line $BORDER,$BORDER $BORDER,$((SIZE-1-BORDER))" \
  -alpha set -channel A -evaluate multiply 0.45 +channel \
  "$hilite"
"${IM_TOOL}" "$overlay" "$hilite" -compose screen -composite "$overlay"

"${IM_TOOL}" -size ${SIZE}x${SIZE} xc:none \
  -stroke "$SHADE" -strokewidth $BORDER -fill none \
  -draw "line $((SIZE-1-BORDER)),$((SIZE-1-BORDER)) $BORDER,$((SIZE-1-BORDER))" \
  -draw "line $((SIZE-1-BORDER)),$((SIZE-1-BORDER)) $((SIZE-1-BORDER)),$BORDER" \
  -alpha set -channel A -evaluate multiply 0.3 +channel \
  "$shade"
"${IM_TOOL}" "$overlay" "$shade" -compose multiply -composite "$overlay"

"${IM_TOOL}" "$tmp_icon" "$overlay" -compose over -composite -colorspace sRGB -strip -depth 8 "$OUT"

rm -f "$tmp_icon" "$overlay" "$hilite" "$shade"
