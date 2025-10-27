#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IM_TOOL="$(command -v magick || command -v convert || true)"
if [[ -z "$IM_TOOL" ]]; then
    echo "ImageMagick (magick/convert) not found in PATH." >&2
    exit 1
fi

button_script="$ROOT/scripts/toolbar_button.sh"
if [[ ! -x "$button_script" ]]; then
    echo "toolbar_button.sh not found or not executable" >&2
    exit 1
fi

ICONS=("Highligher" "PenTool" "Eraser" "CopyImage" "AddText" "MarqueeTool")

for icon in "${ICONS[@]}"; do
    base_png="Resources/${icon}.png"
    if [[ ! -f "$base_png" ]]; then
        echo "Skipping ${icon}: missing ${base_png}" >&2
        continue
    fi

    active_png="Resources/${icon}-active.png"
    active_tiff="Resources/${icon}-active.tiff"
    bundle_png="ScreenshotTool.app/Resources/${icon}-active.png"
    bundle_tiff="ScreenshotTool.app/Resources/${icon}-active.tiff"

    "$button_script" pressed "$base_png" "$active_png"
    "$IM_TOOL" "$active_png" "$active_tiff"

    if [[ -d "ScreenshotTool.app/Resources" ]]; then
        cp "$active_png" "$bundle_png"
        cp "$active_tiff" "$bundle_tiff"
    fi

done
