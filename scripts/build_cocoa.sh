#!/usr/bin/env bash
# Build a Cocoa-native ScreenshotTool.app without GNUstep dependencies.
#
# The sources and resources are the ones GNUmakefile lists for the GNUstep build, so the two
# builds can't drift apart. Of the resources, macOS needs only the symbolic toolbar icons (the
# toolbar's one icon set, tinted as template images) and the cursors; the full-colour icons and
# their TIFFs are GNUstep fallbacks. The result is a universal (arm64 + x86_64) app, signed ad hoc.
#
# Environment:
#   VERSION     version to stamp into Info.plist (default: the manifest's package version)
#   BUILD_NUMBER  CFBundleVersion, which Sparkle compares to find updates (default: the number of
#                 commits, which only grows; Sparkle ignores a "-rc8" suffix when comparing)
#   ARCHS       architectures to build (default: "arm64 x86_64")
#   BUILD_DIR   output directory (default: build/cocoa)
#   SPARKLE     0 builds without the Sparkle updater (default: 1; scripts/fetch_sparkle.sh)
#   FEED_URL    the update feed (default: the release's stable or prerelease feed on Pages)

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script builds the macOS Cocoa target; run it on macOS." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/cocoa}"
OBJ_DIR="${BUILD_DIR}/obj"
APP_DIR="${BUILD_DIR}/ScreenshotTool.app"
APP_MACOS="${APP_DIR}/Contents/MacOS"
APP_RESOURCES="${APP_DIR}/Contents/Resources"
MODULE_CACHE="${BUILD_DIR}/ModuleCache"
ARCHS="${ARCHS:-arm64 x86_64}"
# Sparkle 2.10 needs macOS 12.
MIN_MACOS="12.0"
SPARKLE="${SPARKLE:-1}"
# The update feeds the release job publishes: a prerelease (a version with a "-") follows the
# prerelease channel, as the Windows and Linux builds do.
FEED_BASE="https://danjboyd.github.io/ScreenshotTool/updates/macos"

if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(plutil -extract package.version raw -o - "${ROOT_DIR}/packaging/package.manifest.json")"
fi
VERSION="${VERSION#v}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "${ROOT_DIR}" rev-list --count HEAD 2>/dev/null || echo 1)}"

# Prints the entries of a GNUmakefile list variable (all its "=" and "+=" lines).
makefile_list() {
  awk -v var="$1" '
    $1 == var && ($2 == "=" || $2 == "+=") { collecting = 1; sub(/^[^=]*=/, ""); }
    collecting {
      line = $0
      continued = (line ~ /\\[[:space:]]*$/)
      sub(/\\[[:space:]]*$/, "", line)
      n = split(line, words, /[[:space:]]+/)
      for (i = 1; i <= n; i++) if (words[i] != "") print words[i]
      if (!continued) collecting = 0
    }
  ' "${ROOT_DIR}/GNUmakefile"
}

SOURCES=()
while IFS= read -r line; do SOURCES+=("${line}"); done < <(makefile_list ScreenshotTool_OBJC_FILES)
RESOURCES=()
while IFS= read -r line; do
  case "${line}" in
    *-symbolic.png | Resources/Cursors/*) RESOURCES+=("${line}") ;;
  esac
done < <(makefile_list ScreenshotTool_RESOURCE_FILES)
if [[ ${#SOURCES[@]} -eq 0 || ${#RESOURCES[@]} -eq 0 ]]; then
  echo "Couldn't read the source or resource lists from GNUmakefile." >&2
  exit 1
fi

rm -rf "${APP_DIR}" "${OBJ_DIR}"
mkdir -p "${OBJ_DIR}" "${APP_MACOS}" "${APP_RESOURCES}" "${MODULE_CACHE}"

ARCH_FLAGS=()
for arch in ${ARCHS}; do
  ARCH_FLAGS+=(-arch "${arch}")
done

CFLAGS=(
  "${ARCH_FLAGS[@]}"
  -fobjc-arc
  -fobjc-weak
  -fmodules
  -fmodules-cache-path="${MODULE_CACHE}"
  -O2
  -g
  -Wall -Wextra
  -Wno-deprecated-declarations
  -mmacosx-version-min="${MIN_MACOS}"
  -I"${ROOT_DIR}/Source"
)
LDFLAGS=(
  "${ARCH_FLAGS[@]}"
  -mmacosx-version-min="${MIN_MACOS}"
  -framework AppKit
  -framework Foundation
  -framework CoreGraphics
  -framework CoreText
)

if [[ "${SPARKLE}" != 0 ]]; then
  SPARKLE_DIR="$("${SCRIPT_DIR}/fetch_sparkle.sh")"
  CFLAGS+=(-F"${SPARKLE_DIR}" -DST_HAS_SPARKLE=1)
  LDFLAGS+=(-F"${SPARKLE_DIR}" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
fi

echo "Compiling ${#SOURCES[@]} Objective-C files for ${ARCHS}..."
for src in "${SOURCES[@]}"; do
  base="$(basename "${src}" .m)"
  clang "${CFLAGS[@]}" -c "${ROOT_DIR}/${src}" -o "${OBJ_DIR}/${base}.o"
done

echo "Linking app executable..."
clang "${OBJ_DIR}"/*.o "${LDFLAGS[@]}" -o "${APP_MACOS}/ScreenshotTool"

echo "Generating app icon..."
# The macOS icon is the shape on a transparent canvas (scripts/make_macos_icon.swift).
ICON_SOURCE="${ROOT_DIR}/Resources/ScreenshotToolIcon-macOS.png"
ICONSET_DIR="${BUILD_DIR}/ScreenshotTool.iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"
for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${ICON_SOURCE}" \
    --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "${double}" "${double}" "${ICON_SOURCE}" \
    --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET_DIR}" -o "${APP_RESOURCES}/ScreenshotTool.icns"
rm -rf "${ICONSET_DIR}"

echo "Copying ${#RESOURCES[@]} resources..."
for resource in "${RESOURCES[@]}"; do
  # Keep subdirectories (Resources/Cursors/...) under Contents/Resources.
  relative="${resource#Resources/}"
  mkdir -p "${APP_RESOURCES}/$(dirname "${relative}")"
  cp "${ROOT_DIR}/${resource}" "${APP_RESOURCES}/${relative}"
done

INFO_PLIST="${APP_DIR}/Contents/Info.plist"
cp "${ROOT_DIR}/Resources/Info-cocoa.plist" "${INFO_PLIST}"
plutil -replace CFBundleShortVersionString -string "${VERSION}" "${INFO_PLIST}"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "${INFO_PLIST}"
plutil -replace LSMinimumSystemVersion -string "${MIN_MACOS}" "${INFO_PLIST}"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

if [[ "${SPARKLE}" != 0 ]]; then
  echo "Embedding Sparkle..."
  mkdir -p "${APP_DIR}/Contents/Frameworks"
  ditto "${SPARKLE_DIR}/Sparkle.framework" "${APP_DIR}/Contents/Frameworks/Sparkle.framework"
  # Only sandboxed apps need Sparkle's XPC services.
  rm -rf "${APP_DIR}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
  rm -f "${APP_DIR}/Contents/Frameworks/Sparkle.framework/XPCServices"
  channel="stable"
  [[ "${VERSION}" == *-* ]] && channel="prerelease"
  plutil -replace SUFeedURL -string "${FEED_URL:-${FEED_BASE}/${channel}.xml}" "${INFO_PLIST}"
else
  plutil -remove SUPublicEDKey "${INFO_PLIST}" 2>/dev/null || true
fi

# An ad hoc signature seals the bundle; Apple Silicon won't run an unsigned binary. A Developer
# ID signature replaces it when the app is packaged with CODESIGN_IDENTITY set.
echo "Signing ad hoc..."
"${SCRIPT_DIR}/codesign_macos_app.sh" "${APP_DIR}" -

echo "Cocoa build complete: ${APP_DIR} (version ${VERSION}, build ${BUILD_NUMBER}, $(lipo -archs "${APP_MACOS}/ScreenshotTool"))"
echo "Run it with: open \"${APP_DIR}\""
