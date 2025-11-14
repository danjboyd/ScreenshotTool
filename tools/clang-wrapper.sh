#!/usr/bin/env bash
set -euo pipefail

REAL_CLANG="${CLANG_BIN:-clang}"

filtered_args=()
for arg in "$@"; do
  case "$arg" in
    -mbranch-protection=*|-mbranch-protection=)
      continue
      ;;
  esac
  filtered_args+=("$arg")
done

exec "${REAL_CLANG}" "${filtered_args[@]}"
