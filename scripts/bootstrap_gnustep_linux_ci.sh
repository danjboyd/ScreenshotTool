#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/GNUstep}"
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$PWD/.ci/gnustep-bootstrap}"
MAKE_CMD="${MAKE_CMD:-make -j$(nproc)}"
CC="${CC:-clang}"
CXX="${CXX:-clang++}"
CC_FLAGS="${CC_FLAGS:--fblocks -fobjc-nonfragile-abi}"

sudo apt-get update
sudo apt-get install -y \
  ninja-build cmake make clang llvm-dev gcc-multilib libc6-dev \
  libicu-dev libxml2-dev libxslt1-dev libffi-dev libgmp-dev \
  libavahi-client-dev libgnutls28-dev libudev-dev \
  libpng-dev libtiff-dev libjpeg-dev libfreetype6-dev \
  libx11-dev libxext-dev libxrandr-dev libxft-dev libxmu-dev \
  libxrender-dev libxtst-dev libxt-dev libxcomposite-dev \
  libcairo2-dev libfontconfig1-dev fonts-dejavu-core libcurl4-gnutls-dev libglib2.0-dev \
  libxcursor-dev libcups2-dev libsndfile1-dev libdbus-1-dev \
  rsync imagemagick patchelf curl git pkg-config ca-certificates \
  squashfs-tools desktop-file-utils xvfb xauth \
  openbox xdotool x11-utils

mkdir -p "${BOOTSTRAP_ROOT}"
cd "${BOOTSTRAP_ROOT}"

export PREFIX
export CC
export CXX
export MAKE="${MAKE_CMD}"
export LDFLAGS="-L${PREFIX}/lib -fuse-ld=ld"
export LD_LIBRARY_PATH="${PREFIX}/lib"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
export CPPFLAGS="-I${PREFIX}/include"
export PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}"
export GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles"
export ZSH_VERSION=""
export GNUSTEP_CONFIG_FILE=""
export GNUSTEP_USER_CONFIG_FILE=""

# GNUstep installs its libraries outside the dynamic linker's search path, and sudo drops
# LD_LIBRARY_PATH, so tools that installers run as root (libs-gui's GSspell -RegisterOnly)
# can't find libobjc. Register the directories and refresh the cache after each install.
register_gnustep_libraries() {
  printf '%s\n' \
    "${PREFIX}/lib" \
    "${PREFIX}/lib64" \
    "${PREFIX}/System/Library/Libraries" \
    "${PREFIX}/Local/Library/Libraries" \
    | sudo tee /etc/ld.so.conf.d/gnustep.conf >/dev/null
  sudo ldconfig
}

source_gnustep_env() {
  set +u
  . "${PREFIX}/System/Library/Makefiles/GNUstep.sh"
  set -u
  export PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}"
  export GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles"
}

# Optional third argument: a tag or branch to build instead of the default branch.
clone_or_refresh() {
  local repo_url="$1"
  local dir_name="$2"
  local ref="${3:-}"
  if [ -d "${dir_name}/.git" ]; then
    git -C "${dir_name}" fetch --depth 1 origin ${ref:+"${ref}"}
    git -C "${dir_name}" reset --hard FETCH_HEAD
  else
    git clone --depth 1 ${ref:+--branch "${ref}"} "${repo_url}" "${dir_name}"
  fi
}

# Pin the GNUstep libraries to releases. Upstream master draws exported images incorrectly
# (blank annotations under cairo, near-invisible text under xlib; #45), and these releases
# match the packages the app is developed and tested against.
LIBS_BASE_REF="${LIBS_BASE_REF:-base-1_31_1}"
LIBS_GUI_REF="${LIBS_GUI_REF:-gui-0_32_0}"
LIBS_BACK_REF="${LIBS_BACK_REF:-back-0_32_0}"
# The Adwaita theme, so the unit tests also run under it (#74).
THEME_ADWAITA_REF="${THEME_ADWAITA_REF:-0.1.0-alpha2}"

clone_or_refresh https://github.com/gnustep/libobjc2.git libobjc2
pushd libobjc2 >/dev/null
mkdir -p Build
cd Build
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
sudo ninja install
register_gnustep_libraries
popd >/dev/null

clone_or_refresh https://github.com/apple/swift-corelibs-libdispatch.git libdispatch
pushd libdispatch >/dev/null
mkdir -p Build
cd Build
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
sudo ninja install
register_gnustep_libraries
popd >/dev/null

clone_or_refresh https://github.com/gnustep/tools-make.git gnustep-make
pushd gnustep-make >/dev/null
CCFLAGS="${CC_FLAGS}" CXX="${CXX}" CC="${CC}" \
  ./configure --prefix="${PREFIX}" --with-library-combo=ng-gnu-gnu \
              --enable-objc-arc --enable-native-objc-exceptions \
              --with-layout=gnustep
${MAKE}
sudo ${MAKE} install
register_gnustep_libraries
source_gnustep_env
popd >/dev/null

clone_or_refresh https://github.com/gnustep/libs-base.git libs-base "${LIBS_BASE_REF}"
pushd libs-base >/dev/null
source_gnustep_env
./configure --disable-newkvo --prefix="${PREFIX}"
PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  LDFLAGS="${LDFLAGS} -ldispatch" \
  ${MAKE} GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes
sudo PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install
register_gnustep_libraries
popd >/dev/null

clone_or_refresh https://github.com/gnustep/libs-gui.git libs-gui "${LIBS_GUI_REF}"
pushd libs-gui >/dev/null
source_gnustep_env
./configure --enable-imagemagick --prefix="${PREFIX}"
PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  ${MAKE} GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes
sudo PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install
register_gnustep_libraries
popd >/dev/null

clone_or_refresh https://github.com/gnustep/libs-back.git libs-back "${LIBS_BACK_REF}"
pushd libs-back >/dev/null
source_gnustep_env
PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  ${MAKE} GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes
sudo PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install
register_gnustep_libraries
popd >/dev/null

clone_or_refresh https://github.com/gnustep/plugins-themes-sombre.git plugins-themes-sombre
pushd plugins-themes-sombre >/dev/null
source_gnustep_env
PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  ${MAKE} messages=yes
sudo PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  make install
register_gnustep_libraries
popd >/dev/null

clone_or_refresh https://github.com/danjboyd/plugins-themes-Adwaita.git plugins-themes-adwaita "${THEME_ADWAITA_REF}"
pushd plugins-themes-adwaita >/dev/null
source_gnustep_env
PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  ${MAKE} messages=yes
sudo PATH="${PREFIX}/System/Tools:${PREFIX}/Local/Tools:${PATH}" \
  GNUSTEP_MAKEFILES="${PREFIX}/System/Library/Makefiles" \
  make install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
popd >/dev/null
