#!/bin/bash -e
# build-libffmpeg-mingw32.sh
# 编译 FFmpeg 32位 Windows DLL

TARGET=i686-w64-mingw32
PREFIX="$(pwd)/ffmpeg-install"
JOBS=$(nproc)

echo "=== FFmpeg 32-bit DLL build ==="
echo "Target: $TARGET"
echo "Prefix: $PREFIX"

# 检查源码
if [ ! -f configure ]; then
    echo "Error: configure not found. Run from FFmpeg source directory." >&2
    exit 1
fi

# 配置
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
    --enable-libx265 \
    --enable-libvpx \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libfdk-aac \
    --enable-libass \
    --enable-openssl \
    --enable-libxml2 \
    --disable-autodetect \
    --extra-cflags="-O2 -static-libgcc" \
    --extra-ldflags="-static-libgcc"

# 编译
echo "=== Building with $JOBS jobs ==="
make -j${JOBS}

# 安装
echo "=== Installing ==="
make install

# 收集 DLL
echo "=== Collecting DLLs ==="
mkdir -p ../../artifact
cp -v "$PREFIX"/bin/*.dll ../../artifact/
cp -rv "$PREFIX"/include ../../artifact/ 2>/dev/null || true
cp -rv "$PREFIX"/lib ../../artifact/ 2>/dev/null || true

echo "=== Build complete ==="
ls -la ../../artifact/*.dll 2>/dev/null || echo "No DLLs found"
