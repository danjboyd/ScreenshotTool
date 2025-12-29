#!/usr/bin/env bash
# Reproduce the GitHub Actions AppImage build locally (Ubuntu/Debian hosts).
# Installs build deps, builds GNUstep stack into /usr/GNUstep, builds ScreenshotTool.app,
# and packages an AppImage via scripts/package_appimage.sh.

set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script targets Linux hosts (mirrors the CI AppImage job)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PREFIX="${PREFIX:-/usr/GNUstep}"
MAKE_FLAGS="${MAKE_FLAGS:--j$(nproc)}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/gnustep-build}"
LINUXDEPLOY_DIR="${LINUXDEPLOY_DIR:-/tmp/linuxdeploy}"

if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "Run as root or install sudo to allow package installs and /usr/GNUstep writes." >&2
    exit 1
  fi
else
  SUDO=""
fi

export ZSH_VERSION="${ZSH_VERSION:-}"

echo "== Installing build dependencies =="
export DEBIAN_FRONTEND=noninteractive
${SUDO} apt-get update
${SUDO} apt-get install -y \
  ninja-build cmake make clang llvm-dev gcc-multilib libc6-dev \
  libicu-dev libxml2-dev libxslt1-dev libffi-dev libgmp-dev \
  libavahi-client-dev libgnutls28-dev libudev-dev \
  libpng-dev libtiff-dev libjpeg-dev libfreetype6-dev \
  libx11-dev libxext-dev libxrandr-dev libxft-dev libxmu-dev \
  libxrender-dev libxtst-dev libxt-dev libxcomposite-dev \
  libxcursor-dev libcups2-dev libsndfile1-dev libdbus-1-dev \
  rsync imagemagick patchelf curl git ca-certificates pkg-config

mkdir -p "${BUILD_ROOT}"
cd "${BUILD_ROOT}"

echo "== Building GNUstep stack into ${PREFIX} =="
export CC=clang
export CXX=clang++
export LDFLAGS="-L${PREFIX}/lib -fuse-ld=ld"
export MAKE="make ${MAKE_FLAGS}"
export CPPFLAGS="-I${PREFIX}/include"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
cc_flags="-fblocks -fobjc-nonfragile-abi"

set +e
rm -rf libobjc2 libdispatch gnustep-make libs-base libs-gui libs-back plugins-themes-sombre
set -e

git clone --depth 1 https://github.com/gnustep/libobjc2.git
pushd libobjc2
mkdir -p Build && cd Build
cmake -G Ninja .. \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_OBJC_COMPILER="${CC}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  -DTESTS=OFF
ninja
${SUDO} ninja install
popd

git clone --depth 1 https://github.com/apple/swift-corelibs-libdispatch.git libdispatch
pushd libdispatch
mkdir -p Build && cd Build
cmake -G Ninja .. \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  -DENABLE_TESTING=OFF \
  -DWITH_LIBKQUEUE=ON \
  -DWITH_BLOCKS_RUNTIME=ON
ninja
${SUDO} ninja install
popd

git clone https://github.com/gnustep/tools-make.git gnustep-make
pushd gnustep-make
CCFLAGS="${cc_flags}" CXX="${CXX}" CC="${CC}" \
  ./configure --prefix="${PREFIX}" --with-library-combo=ng-gnu-gnu \
              --enable-objc-arc --enable-native-objc-exceptions \
              --with-layout=gnustep
${MAKE}
${SUDO} ${MAKE} install
set +u
. "${PREFIX}/System/Library/Makefiles/GNUstep.sh"
set -u
popd

git clone https://github.com/gnustep/libs-base.git
pushd libs-base
set +u
. "${PREFIX}/System/Library/Makefiles/GNUstep.sh"
set -u
./configure --disable-newkvo --prefix="${PREFIX}"
LDFLAGS="${LDFLAGS} -ldispatch" ${MAKE} GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes
${SUDO} make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install
popd

git clone https://github.com/gnustep/libs-gui.git
pushd libs-gui
set +u
. "${PREFIX}/System/Library/Makefiles/GNUstep.sh"
set -u
./configure --enable-imagemagick --prefix="${PREFIX}"
${MAKE} GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes
${SUDO} make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install
popd

git clone https://github.com/gnustep/libs-back.git
pushd libs-back
set +u
. "${PREFIX}/System/Library/Makefiles/GNUstep.sh"
set -u
${MAKE} GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes
${SUDO} make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install
popd

git clone https://github.com/gnustep/plugins-themes-sombre.git
pushd plugins-themes-sombre
${MAKE} messages=yes
${SUDO} make install
popd

echo "== Building ScreenshotTool.app =="
cd "${ROOT_DIR}"
set +u
. "${PREFIX}/System/Library/Makefiles/GNUstep.sh"
set -u
make -j"$(nproc)"

echo "== Downloading linuxdeploy (AppImage + plugin) =="
mkdir -p "${LINUXDEPLOY_DIR}"
curl -L https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage -o "${LINUXDEPLOY_DIR}/linuxdeploy"
curl -L https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage -o "${LINUXDEPLOY_DIR}/linuxdeploy-plugin-appimage"
chmod +x "${LINUXDEPLOY_DIR}/linuxdeploy" "${LINUXDEPLOY_DIR}/linuxdeploy-plugin-appimage"

echo "== Packaging AppImage =="
LINUXDEPLOY="${LINUXDEPLOY_DIR}/linuxdeploy" \
LINUXDEPLOY_PLUGIN_APPIMAGE="${LINUXDEPLOY_DIR}/linuxdeploy-plugin-appimage" \
GNUSTEP_ROOT="${PREFIX}" \
  "${SCRIPT_DIR}/package_appimage.sh"

echo "== Done: Staging/ScreenshotTool-x86_64.AppImage =="
