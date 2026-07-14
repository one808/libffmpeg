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
export PKG_CONFIG=/usr/bin/pkg-config
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

# Helper: build cmake project
build_cmake() {
    local name=$1 url=$2 cmake_args=$3
    echo "=== Building $name (cmake) ==="
    if [ ! -d "$DEPS/$name" ]; then
        git clone --depth 1 "$url" "$DEPS/$name"
    fi
    rm -rf "$DEPS/${name}_build"
    mkdir -p "$DEPS/${name}_build"
    cd "$DEPS/${name}_build"
    cmake "$DEPS/$name" \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_SYSTEM_PROCESSOR=x86 \
        -DCMAKE_C_COMPILER=${TARGET}-gcc \
        -DCMAKE_CXX_COMPILER=${TARGET}-g++ \
        -DCMAKE_RC_COMPILER=${TARGET}-windres \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        $cmake_args 2>&1 | tail -5
    make -j$JOBS
    make install
    cd "$WORK_DIR"
}

# Helper: build meson project
build_meson() {
    local name=$1 url=$2 meson_args=$3
    echo "=== Building $name (meson) ==="
    if [ ! -d "$DEPS/$name" ]; then
        git clone --depth 1 "$url" "$DEPS/$name"
    fi
    rm -rf "$DEPS/${name}_build"
    mkdir -p "$DEPS/${name}_build"
    cd "$DEPS/${name}_build"
    meson setup "$DEPS/$name" \
        --cross-file /tmp/meson-cross.ini \
        --prefix="$PREFIX" \
        --default-library=static \
        --buildtype=release \
        $meson_args 2>&1 | tail -5
    ninja
    ninja install
    cd "$WORK_DIR"
}

# Create meson cross-compilation file
cat > /tmp/meson-cross.ini << MESONEOF
[binaries]
c = '${TARGET}-gcc'
cpp = '${TARGET}-g++'
ar = '${TARGET}-ar'
strip = '${TARGET}-strip'
pkgconfig = 'pkg-config'
windres = '${TARGET}-windres'

[host_machine]
system = 'windows'
cpu_family = 'x86'
cpu = 'i686'
endian = 'little'

[built-in properties]
c_args = ['-I${PREFIX}/include']
c_link_args = ['-L${PREFIX}/lib']
cpp_args = ['-I${PREFIX}/include']
cpp_link_args = ['-L${PREFIX}/lib']
MESONEOF

# 1. dav1d (AV1 decoder)
build_meson "dav1d" "https://code.videolan.org/videolan/dav1d.git" \
    "-Denable_tests=false -Denable_examples=false -Dlogging=false"


export ASM_NASM=/usr/bin/nasm
# 3. aom (AV1 encoder/decoder)
echo "=== Building aom ==="
if [ ! -d "$DEPS/aom" ]; then
    git clone --depth 1 https://aomedia.googlesource.com/aom "$DEPS/aom"
fi
mkdir -p "$DEPS/aom_build"
cd "$DEPS/aom_build"
cmake "$DEPS/aom" \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_SYSTEM_PROCESSOR=x86 \
    -DCMAKE_C_COMPILER=${TARGET}-gcc \
    -DCMAKE_CXX_COMPILER=${TARGET}-g++ \
    -DCMAKE_RC_COMPILER=${TARGET}-windres \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_EXAMPLES=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_DOCS=OFF \
    -DCMAKE_ASM_NASM_COMPILER=/usr/bin/nasm \
    -DAOM_TARGET_CPU=x86 \
    -DCMAKE_ASM_NASM_OBJECT_FORMAT=win32 \
    -DENABLE_ASM=OFF 2>&1 | tail -10
make -j$JOBS
make install
cd "$WORK_DIR"

# 4. openh264 (Cisco H.264) - uses meson
build_meson "openh264" "https://github.com/cisco/openh264.git" \
    "-Dtests=disabled"

# 5. vid.stab (video stabilization)
build_cmake "vid.stab" "https://github.com/georgmartius/vid.stab.git" \
    "-DUSE_OMP=OFF"

# 6. zimg (high-quality scaling) - autotools (needs submodule)
echo "=== Building zimg ==="
if [ ! -d "$DEPS/zimg" ]; then
    git clone --depth 1 --recurse-submodules https://github.com/sekrit-twc/zimg.git "$DEPS/zimg"
fi
cd "$DEPS/zimg"
./autogen.sh 2>/dev/null || true
./configure --host=$TARGET --prefix="$PREFIX" --disable-doc --enable-static --disable-shared
make -j$JOBS
make install
cd "$WORK_DIR"

# 7. rubberband (time-stretching)
build_meson "rubberband" "https://github.com/breakfastquay/rubberband.git" \
    "-Dfft=builtin -Dresampler=builtin -Djni=disabled"

# 8. libsrt (SRT protocol)
build_cmake "srt" "https://github.com/Haivision/srt.git" \
    "-DENABLE_SHARED=OFF -DENABLE_APPS=OFF -DENABLE_TESTING=OFF -DENABLE_TEST_PROGRAMS=OFF -DENABLE_ENCRYPTION=OFF -DENABLE_SOCKS=OFF"


# 9. Build FFmpeg
echo "=== Building FFmpeg ==="

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
    --enable-nvdec \
    --enable-nvenc \
    --enable-libx264 \
    --enable-libopenh264 \
    --enable-libvidstab \
    --enable-libzimg \
    --enable-librubberband \
    --enable-libsrt \
    --enable-libdav1d \
    --enable-libaom \
    --enable-libvpx \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libfdk-aac \
    --enable-openssl \
    --disable-debug \
    --disable-doc \
    --disable-programs \
    --extra-cflags="$EXTRA_CFLAGS" \
    --extra-ldflags="$EXTRA_LDFLAGS" \
    --extra-libs="$EXTRA_LIBS"

make -j$JOBS
make install

# 10. Package artifact
echo "=== Package artifact ==="
echo "Contents of artifact dir:"
ls -la "$WORK_DIR/artifact/bin/" 2>/dev/null || echo "No bin dir"
echo "BUILD COMPLETE"
