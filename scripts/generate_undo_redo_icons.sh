#!/usr/bin/env bash
# Draw the Undo and Redo toolbar icons (#101): a curved arrow in the symbolic icons' grey, at 8x
# and scaled down for clean edges; Redo is Undo mirrored. Needs ImageMagick.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../Resources"
convert -size 192x192 xc:none -fill none -stroke '#3D3846' -strokewidth 17 \
  -draw "stroke-linecap round stroke-linejoin round path 'M 68 72 L 112 72 A 40 40 0 0 1 112 152 L 80 152'" \
  -stroke none -fill '#3D3846' -draw "polygon 20,72 76,28 76,116" \
  -resize 24x24 PNG32:Undo-symbolic.png
convert Undo-symbolic.png -flop PNG32:Redo-symbolic.png
