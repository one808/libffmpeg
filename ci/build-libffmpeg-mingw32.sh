#!/bin/bash -e
# build-libffmpeg-mingw32.sh
# 编译 FFmpeg 32位 Windows DLL（含所有外部库）

TARGET=i686-w64-mingw32
PREFIX="$(pwd)/ffmpeg-install"
DEPS="$(pwd)/deps"
JOBS=$(nproc)

export CC=${TARGET}-gcc
export CXX=${TARGET}-g++
export AR=${TARGET}-ar
export RANLIB=${TARGET}-ranlib
export STRIP=${TARGET}-strip

echo "=== FFmpeg 32-bit DLL build ==="
echo "Target: $TARGET"

mkdir -p "$PREFIX" "$DEPS"

build_dep() {
    local name=$1 url=$2 configure_args=$3
    echo "=== Building $name ==="
    if [ ! -d "$DEPS/$name" ]; then
        git clone --depth 1 "$url" "$DEPS/$name"
    fi
    cd "$DEPS/$name"
    if [ ! -f Makefile ] && [ ! -f configure ]; then
        ./autogen.sh 2>/dev/null || true
    fi
    if [ -f configure ]; then
        if echo "$configure_args" | grep -q "\-\-target"; then
            ./configure --prefix="$PREFIX" $configure_args --enable-static --disable-shared
        else
            ./configure --host=$TARGET --prefix="$PREFIX" $configure_args --enable-static --disable-shared
        fi
    fi
    make -j$JOBS
    make install
    cd -
}

# 1. x264
build_dep "x264" "https://code.videolan.org/videolan/x264.git" \
    "--enable-pic --enable-static --disable-cli --disable-lavf"

# 2. libvpx
build_dep "libvpx" "https://chromium.googlesource.com/webm/libvpx.git" \
    "--target=generic-gnu --enable-vp8 --enable-vp9 --enable-static --disable-shared --disable-examples --disable-tools --disable-unit-tests"

# 3. lame
build_dep "lame" "https://github.com/lameproject/lame.git" \
    "--enable-nasm --disable-frontend --disable-mp3x"

# 4. opus
build_dep "opus" "https://github.com/xiph/opus.git" \
    "--enable-static --disable-shared --disable-extra-programs --disable-doc"

# 5. fdk-aac
build_dep "fdk-aac" "https://github.com/mstorsjo/fdk-aac.git" \
    "--enable-static --disable-shared"

# 6. ogg + vorbis
build_dep "ogg" "https://github.com/xiph/ogg.git" \
    "--enable-static --disable-shared"
build_dep "vorbis" "https://github.com/xiph/vorbis.git" \
    "--enable-static --disable-shared --disable-examples"

