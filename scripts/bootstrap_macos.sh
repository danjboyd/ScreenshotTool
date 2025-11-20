#!/usr/bin/env bash
# Install and prime the GNUstep/Cocoa toolchain on macOS for ScreenshotTool builds.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This bootstrap is intended for macOS hosts only." >&2
  exit 1
fi

BREW_BIN="${BREW:-$(command -v brew || true)}"
if [[ -z "${BREW_BIN}" ]]; then
  echo "Homebrew is required; install it from https://brew.sh and re-run this script." >&2
  exit 1
fi

declare -a PACKAGES=(
  gnustep-make
  gnustep-base
  pkg-config
  freetype
  fontconfig
  make
)

echo "Installing/validating Homebrew packages: ${PACKAGES[*]}"
for pkg in "${PACKAGES[@]}"; do
  if "${BREW_BIN}" ls --versions "${pkg}" >/dev/null 2>&1; then
    echo " - ${pkg} already installed"
  else
    echo " - installing ${pkg}"
    "${BREW_BIN}" install "${pkg}"
  fi
done

GNUSTEP_PREFIX="$(${BREW_BIN} --prefix gnustep-make 2>/dev/null || true)"
if [[ -n "${GNUSTEP_PREFIX}" ]]; then
  export PATH="${GNUSTEP_PREFIX}/libexec:${PATH}"
fi

if ! command -v gnustep-config >/dev/null 2>&1; then
  echo "gnustep-config not found after installation; ensure Homebrew's bin directory and gnustep-make/libexec are on PATH." >&2
  exit 1
fi

GNUSTEP_MAKEFILES="$(gnustep-config --variable=GNUSTEP_MAKEFILES)"
GNUSTEP_SH="$(dirname "${GNUSTEP_MAKEFILES}")/GNUstep.sh"
GNUSTEP_SYSTEM_TOOLS="$(gnustep-config --variable=GNUSTEP_SYSTEM_TOOLS 2>/dev/null || true)"
GNUSTEP_SYSTEM_LIBRARY="$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY 2>/dev/null || true)"

cat <<EOF

GNUstep detected.

Add these exports to your shell (or source this in your CI) before building:
  export GNUSTEP_MAKEFILES="${GNUSTEP_MAKEFILES}"
  source "${GNUSTEP_SH}"
  export PATH="${GNUSTEP_SYSTEM_TOOLS:-/usr/GNUstep/System/Tools}:\${PATH}"
  export LD_LIBRARY_PATH="${GNUSTEP_SYSTEM_LIBRARY:-/usr/GNUstep/System}/Libraries:\${LD_LIBRARY_PATH:-}"
  export DYLD_LIBRARY_PATH="${GNUSTEP_SYSTEM_LIBRARY:-/usr/GNUstep/System}/Libraries:\${DYLD_LIBRARY_PATH:-}"

Then invoke ./scripts/build_macos.sh to compile the app bundle.
EOF
