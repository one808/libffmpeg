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
    "--target=${TARGET} --enable-vp8 --enable-vp9 --enable-static --disable-shared --disable-examples --disable-tools --disable-unit-tests"

# 3. lame
build_dep "lame" "https://svn.code.sf.net/p/lame/svn/trunk/lame" \
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

# 7. openssl
build_dep "openssl" "https://github.com/openssl/openssl.git" \
    "no-shared no-tests no-ssl2 no-ssl3 no-zlib no-comp no-asm enable-ec_nistp_64_gcc_128"

echo "=== Dependencies built ==="

if [ ! -f configure ]; then
    echo "Error: configure not found. Run from FFmpeg source directory." >&2
    exit 1
fi

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"

./configure \
    --target-os=mingw32 \
    --arch=x86 \
    --cross-prefix=${TARGET}- \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    --disable-programs \
    --disable-doc \
    --disable-debug \
    --enable-gpl \
    --enable-version3 \
    --enable-nonfree \
    --enable-runtime-cpudetect \
    --enable-dxva2 \
    --enable-d3d11va \
    --enable-nvdec \
    --enable-nvenc \
    --enable-libx264 \
    --enable-libvpx \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libfdk-aac \
    --enable-openssl \
    --extra-cflags="-I$PREFIX/include -O2 -static-libgcc" \
    --extra-ldflags="-L$PREFIX/lib -static-libgcc" \
    --extra-libs="-lpthread"

echo "=== Building FFmpeg with $JOBS jobs ==="
make -j$JOBS

echo "=== Installing ==="
make install

echo "=== Collecting DLLs ==="
mkdir -p ../../artifact
cp -v "$PREFIX"/bin/*.dll ../../artifact/ 2>/dev/null || true
cp -rv "$PREFIX"/include ../../artifact/ 2>/dev/null || true
cp -rv "$PREFIX"/lib ../../artifact/ 2>/dev/null || true

echo "=== Build complete ==="
ls -la ../../artifact/*.dll 2>/dev/null || echo "No DLLs found"
