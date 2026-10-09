#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="${ROOT}/Resources"

patterns=(
  "*-symbolic.png"
)

for pattern in "${patterns[@]}"; do
  for file in ${BASE_DIR}/${pattern}; do
    [[ -e "$file" ]] || continue
    tmp="${file}.tmp"
    magick "$file" -strip -type TrueColorAlpha -depth 8 "$tmp"
    mv "$tmp" "$file"
    echo "Normalized $(basename "$file")"
  done
 done
