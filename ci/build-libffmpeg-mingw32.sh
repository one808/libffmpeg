#!/bin/bash -e
# build-libffmpeg-mingw32.sh
# 编译 FFmpeg 32位 Windows DLL（含所有外部库）

TARGET=i686-w64-mingw32
WORK_DIR="$(pwd)"
PREFIX="$(pwd)/ffmpeg-install"
DEPS="$(pwd)/deps"
JOBS=$(nproc)

export CC=${TARGET}-gcc
export CXX=${TARGET}-g++
export AR=${TARGET}-ar
export RANLIB=${TARGET}-ranlib
export STRIP=${TARGET}-strip

export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig:$PKG_CONFIG_PATH"
echo "=== FFmpeg 32-bit DLL build ==="
echo "Target: $TARGET"
echo "WORK_DIR: $WORK_DIR"

mkdir -p "$PREFIX" "$DEPS" "$WORK_DIR/artifact"

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
    cd "$WORK_DIR"
}

# 1. x264
build_dep "x264" "https://code.videolan.org/videolan/x264.git" \
    "--enable-pic --enable-static --disable-cli --disable-lavf"

# 2. libvpx
build_dep "libvpx" "https://chromium.googlesource.com/webm/libvpx.git" \
    "--target=x86-win32-gcc --enable-vp8 --enable-vp9 --enable-static --disable-shared --disable-examples --disable-tools --disable-unit-tests --enable-multithread"

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

# 8. Build FFmpeg
echo "=== Building FFmpeg ==="
cd "$WORK_DIR"

EXTRA_LIBS="-L$PREFIX/lib"
EXTRA_CFLAGS="-I$PREFIX/include"
EXTRA_LDFLAGS="-L$PREFIX/lib"

./configure \
    --target-os=mingw32 \
    --arch=x86 \
    --cross-prefix=${TARGET}- \
    --prefix="$WORK_DIR/artifact" \
    --enable-shared \
    --disable-static \
    --enable-gpl \
    --enable-version3 \
    --enable-nonfree \
    --enable-dxva2 \
    --enable-d3d11va \
    --disable-nvdec \
    --disable-nvenc \
    --enable-libx264 \
    --enable-libvpx \
    --enable-libmp3lame \
    --enable-libopus \
    --disable-libvorbis \
    --disable-libfdk-aac \
    --disable-openssl \
    --disable-libass \
    --disable-debug \
    --disable-doc \
    --disable-programs \
    --extra-cflags="$EXTRA_CFLAGS" \
    --extra-ldflags="$EXTRA_LDFLAGS" \
    --extra-libs="$EXTRA_LIBS"

make -j$JOBS
make install

# 9. Package artifact
echo "=== Package artifact ==="
echo "Contents of artifact dir:"
ls -la "$WORK_DIR/artifact/bin/" 2>/dev/null || echo "No bin dir"
echo "BUILD COMPLETE"
