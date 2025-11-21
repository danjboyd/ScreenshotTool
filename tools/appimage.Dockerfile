FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PREFIX=/usr/GNUstep
ENV ZSH_VERSION=
ENV CPPFLAGS=-I${PREFIX}/include
ENV PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig
ENV LD_LIBRARY_PATH=${PREFIX}/lib

# Install build prerequisites matching GitHub Actions.
RUN apt-get update && apt-get install -y \
    ninja-build cmake make clang llvm-dev gcc-multilib libc6-dev \
    libicu-dev libxml2-dev libxslt1-dev libffi-dev libgmp-dev \
    libavahi-client-dev libgnutls28-dev libudev-dev \
    libpng-dev libtiff-dev libjpeg-dev libfreetype6-dev \
    libx11-dev libxext-dev libxrandr-dev libxft-dev libxmu-dev \
    libxrender-dev libxtst-dev libxt-dev libxcomposite-dev \
    libxcursor-dev libcups2-dev libsndfile1-dev libdbus-1-dev \
    rsync imagemagick patchelf curl git ca-certificates pkg-config \
    && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-c"]

WORKDIR /tmp/gnustep-build

RUN set -euo pipefail \
    && export CC=clang CXX=clang++ LDFLAGS="-L${PREFIX}/lib -fuse-ld=ld" MAKE="make -j$(nproc)" cc_flags="-fblocks -fobjc-nonfragile-abi" \
    && git clone --depth 1 https://github.com/gnustep/libobjc2.git \
    && cd libobjc2 && mkdir -p Build && cd Build \
    && cmake -G Ninja .. \
         -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
         -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_C_COMPILER="${CC}" \
         -DCMAKE_CXX_COMPILER="${CXX}" \
         -DCMAKE_OBJC_COMPILER="${CC}" \
         -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
         -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
         -DTESTS=OFF \
    && ninja && ninja install \
    && cd /tmp/gnustep-build \
    && git clone --depth 1 https://github.com/apple/swift-corelibs-libdispatch.git libdispatch \
    && cd libdispatch && mkdir -p Build && cd Build \
    && cmake -G Ninja .. \
         -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
         -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_C_COMPILER="${CC}" \
         -DCMAKE_CXX_COMPILER="${CXX}" \
         -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
         -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
         -DENABLE_TESTING=OFF \
         -DWITH_LIBKQUEUE=ON \
         -DWITH_BLOCKS_RUNTIME=ON \
    && ninja && ninja install \
    && cd /tmp/gnustep-build \
    && git clone https://github.com/gnustep/tools-make.git gnustep-make \
    && cd gnustep-make \
    && CCFLAGS="${cc_flags}" CXX="${CXX}" CC="${CC}" \
         ./configure --prefix="${PREFIX}" --with-library-combo=ng-gnu-gnu \
                     --enable-objc-arc --enable-native-objc-exceptions \
                     --with-layout=gnustep \
    && ${MAKE} \
    && ${MAKE} install \
    && set +u && . "${PREFIX}/System/Library/Makefiles/GNUstep.sh" && set -u \
    && cd /tmp/gnustep-build \
    && git clone https://github.com/gnustep/libs-base.git \
    && cd libs-base \
    && set +u && . "${PREFIX}/System/Library/Makefiles/GNUstep.sh" && set -u \
    && ./configure --disable-newkvo --prefix="${PREFIX}" \
    && LDFLAGS="${LDFLAGS} -ldispatch" ${MAKE} GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes \
    && make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install \
    && cd /tmp/gnustep-build \
    && git clone https://github.com/gnustep/libs-gui.git \
    && cd libs-gui \
    && set +u && . "${PREFIX}/System/Library/Makefiles/GNUstep.sh" && set -u \
    && ./configure --enable-imagemagick --prefix="${PREFIX}" \
    && ${MAKE} GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes \
    && make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install \
    && cd /tmp/gnustep-build \
    && git clone https://github.com/gnustep/libs-back.git \
    && cd libs-back \
    && set +u && . "${PREFIX}/System/Library/Makefiles/GNUstep.sh" && set -u \
    && ${MAKE} GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes \
    && make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install \
    && cd /tmp/gnustep-build \
    && git clone https://github.com/gnustep/plugins-themes-sombre.git \
    && cd plugins-themes-sombre \
    && ${MAKE} messages=yes \
    && make install \
    && cd / \
    && rm -rf /tmp/gnustep-build

WORKDIR /src

CMD ["bash"]
