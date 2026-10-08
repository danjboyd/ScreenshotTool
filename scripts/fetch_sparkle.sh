#!/usr/bin/env bash
# Downloads the pinned Sparkle release (the macOS updater) once, checks its SHA-256, and prints
# the folder holding Sparkle.framework and Sparkle's tools (bin/sign_update, ...).
#
# Usage: scripts/fetch_sparkle.sh          (into build/third_party/Sparkle-<version>)

set -euo pipefail

SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEST="${ROOT_DIR}/build/third_party/Sparkle-${SPARKLE_VERSION}"

if [[ ! -d "${DEST}/Sparkle.framework" ]]; then
  archive="$(mktemp -d)/Sparkle-${SPARKLE_VERSION}.tar.xz"
  curl --fail --location --silent --show-error --retry 3 --output "${archive}" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  actual="$(shasum -a 256 "${archive}" | cut -d' ' -f1)"
  if [[ "${actual}" != "${SPARKLE_SHA256}" ]]; then
    echo "fetch_sparkle: checksum mismatch for Sparkle ${SPARKLE_VERSION} (${actual})" >&2
    exit 1
  fi
  rm -rf "${DEST}"
  mkdir -p "${DEST}"
  tar -xJf "${archive}" -C "${DEST}" Sparkle.framework bin LICENSE
  rm -f "${archive}"
fi
echo "${DEST}"
