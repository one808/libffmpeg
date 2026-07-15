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

# 1. x264
build_dep "x264" "https://code.videolan.org/videolan/x264.git" \
    "--enable-pic --enable-static --disable-cli --disable-lavf"

# 2. dav1d (AV1 decoder)
build_meson "dav1d" "https://code.videolan.org/videolan/dav1d.git" \
    "-Denable_tests=false -Denable_examples=false -Dlogging=false"


# 2. libvpx
build_dep "libvpx" "https://chromium.googlesource.com/webm/libvpx.git" \
    "--target=x86-win32-gcc --enable-vp8 --enable-vp9 --enable-static --disable-shared --disable-examples --disable-tools --disable-unit-tests --disable-multithread"

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

# Fix vorbis.pc for static linking
echo "=== Fixing vorbis.pc: add -logg ==="
python3 -c "
import os, glob
prefix = os.environ.get('PREFIX', '$PREFIX')
for pc in glob.glob(os.path.join(prefix, 'lib', 'pkgconfig', 'vorbis*.pc')):
    c = open(pc).read()
    changed = False
    if 'Libs:' in c and '-logg' not in c:
        c = c.replace('Libs: -L\${libdir} -lvorbis ', 'Libs: -L\${libdir} -lvorbis -logg -lm')
        c = c.replace('Libs: -L\${libdir} -lvorbisenc ', 'Libs: -L\${libdir} -lvorbisenc -lvorbis -logg -lm')
        c = c.replace('Libs: -L\${libdir} -lvorbisfile ', 'Libs: -L\${libdir} -lvorbisfile -lvorbis -logg -lm')
        changed = True
    if 'vorbisenc.pc' in pc and 'Requires:' not in c:
        c = c.replace('Description:', 'Requires: vorbis\nDescription:')
        changed = True
    if 'vorbisfile.pc' in pc and 'Requires:' not in c:
        c = c.replace('Description:', 'Requires: vorbis\nDescription:')
        changed = True
    if changed:
        open(pc, 'w').write(c)
        print(f'Fixed {os.path.basename(pc)}')
    else:
        print(f'No changes needed for {os.path.basename(pc)}')
"
cat "$PREFIX/lib/pkgconfig/vorbis.pc"

# 7. NVIDIA Video Codec SDK headers
echo "=== Downloading NVIDIA Video Codec SDK ==="
mkdir -p "$PREFIX/include/ffnvcodec"
git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git /tmp/nv-codec-headers 2>/dev/null || \
  git clone --depth 1 https://git.videolan.org/git/ffmpeg/nv-codec-headers.git /tmp/nv-codec-headers 2>/dev/null || true
if [ -d /tmp/nv-codec-headers/include/ffnvcodec ]; then
    cp /tmp/nv-codec-headers/include/ffnvcodec/*.h "$PREFIX/include/ffnvcodec/"
    cp /tmp/nv-codec-headers/ffnvcodec.pc "$PREFIX/lib/pkgconfig/" 2>/dev/null || true
    sed -i "s|prefix=.*|prefix=$PREFIX|" "$PREFIX/lib/pkgconfig/ffnvcodec.pc" 2>/dev/null || true
    echo "NVIDIA Video Codec SDK headers installed"
else
    echo "NVIDIA Video Codec SDK not found, skipping"
fi

# 8. OpenSSL
echo "=== Building OpenSSL ==="
if [ ! -d "$DEPS/openssl" ]; then
    git clone --depth 1 --branch openssl-3.5.1 https://github.com/openssl/openssl.git "$DEPS/openssl"
fi
cd "$DEPS/openssl"
perl ./Configure mingw \
    --prefix="$PREFIX" \
    no-shared no-asm no-tests no-engine no-dynamic-engine no-comp no-legacy 2>&1 | tail -10
make generate 2>/dev/null || true
make -j$JOBS build_libs 2>&1 | tail -5

mkdir -p "$PREFIX/include/openssl" "$PREFIX/lib"
cp -r include/openssl/ "$PREFIX/include/openssl/" 2>/dev/null || true
cp libssl.a "$PREFIX/lib/" 2>/dev/null || true
cp libcrypto.a "$PREFIX/lib/" 2>/dev/null || true
cat > "$PREFIX/lib/pkgconfig/openssl.pc" << OPEOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenSSL
Description: Secure Sockets Layer and cryptography libraries
Version: 3.5.1
Requires:
Libs: -L\${libdir} -lssl -lcrypto
Cflags: -I\${includedir}
OPEOF
echo "OpenSSL installed: $(ls $PREFIX/lib/libssl.a $PREFIX/lib/libcrypto.a 2>/dev/null | wc -l) libs"
cd "$WORK_DIR"

export ASM_NASM=/usr/bin/nasm
# 9. aom (AV1 encoder/decoder)
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
