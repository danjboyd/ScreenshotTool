#!/usr/bin/env bash
set -euo pipefail

TARGET_SIZE="${TARGET_SIZE:-24}"
INNER_SIZE="${INNER_SIZE:-20}"
SHARPEN="${SHARPEN:-0x1+0.75+0.02}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="${ROOT}/Resources"

icons=(
  AddText
  CopyImage
  Eraser
  Highligher
  MarqueeTool
  PenTool
  Preferences
)
variants=(dark light dark-active light-active)

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick 'magick' binary is required but not found in PATH." >&2
  exit 1
fi

for icon in "${icons[@]}"; do
  for variant in "${variants[@]}"; do
    src="${RESOURCES_DIR}/${icon}-${variant}.png"
    dst="${RESOURCES_DIR}/${icon}-${variant}-gnustep.png"
    if [[ ! -f "${src}" ]]; then
      echo "Skipping ${icon}-${variant}: ${src} missing." >&2
      continue
    fi
    magick "${src}" \
      -resize "${INNER_SIZE}x${INNER_SIZE}" \
      -unsharp "${SHARPEN}" \
      -background none \
      -gravity center \
      -extent "${TARGET_SIZE}x${TARGET_SIZE}" \
      -strip -type TrueColorAlpha -depth 8 \
      "${dst}"
    echo "Wrote ${dst}"
  done
done

echo "Done. GNUstep-specific toolbar icons now live alongside the originals."
