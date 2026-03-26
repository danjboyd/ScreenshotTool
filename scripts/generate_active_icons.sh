#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="${ROOT}/Resources"

STROKE_COLOR="rgba(94,242,255,0.95)"
FILL_COLOR="rgba(94,242,255,0.22)"
CANVAS=32
OUTER_RADIUS=6
INNER_RADIUS=5
STROKE_WIDTH=2

process_variant() {
  local stem="$1"
  local theme="$2"
  local src="${BASE_DIR}/${stem}-${theme}.png"
  local dest="${BASE_DIR}/${stem}-${theme}-active.png"
  if [[ ! -f "$src" ]]; then
    echo "Missing $src; skipping." >&2
    return
  fi
  magick "$src" \
    \( -size ${CANVAS}x${CANVAS} xc:none -stroke "$STROKE_COLOR" -strokewidth $STROKE_WIDTH -fill none \
       -draw "roundrectangle 1,1,$((CANVAS-2)),$((CANVAS-2)),$OUTER_RADIUS,$OUTER_RADIUS" \) \
    -compose over -composite \
    \( -size ${CANVAS}x${CANVAS} xc:none -fill "$FILL_COLOR" \
       -draw "roundrectangle 3,3,$((CANVAS-3)),$((CANVAS-3)),$INNER_RADIUS,$INNER_RADIUS" -blur 0x3 \) \
    -compose over -composite \
    -strip -type TrueColorAlpha -depth 8 \
    "$dest"
  echo "Created $dest"
}

while read -r name stem; do
  [[ -z "$name" ]] && continue
  for theme in dark light; do
    process_variant "$stem" "$theme"
  done
done <<'MAP'
Select MarqueeTool
Highlighter Highligher
Pen PenTool
Text AddText
Eraser Eraser
Copy CopyImage
Preferences Preferences
MAP

"${ROOT}/scripts/generate_toolbar_icons.sh"
