# libffmpeg

通过 GitHub Actions 自动编译 FFmpeg 32位 Windows DLL。

## 功能

- 自动检测上游 FFmpeg 新版本
- 交叉编译 32位 Windows DLL（MinGW32）
- 构建后自动发布到 GitHub Releases
- 支持硬件加速：DXVA2、D3D11VA、NVDEC、NVENC
- 支持编解码器：x264、x265、vpx、mp3lame、opus、vorbis、fdk-aac、ass

## 工作流

| 工作流 | 说明 |
|--------|------|
| `build-libffmpeg.yml` | 自动检测版本 + 构建 + Release |
| `reset-build-version.yml` | 重置版本记录，用于重新构建 |

## 下载

从 [Releases](https://github.com/one808/libffmpeg/releases) 下载对应平台的 ZIP 包。

## 本地构建

```bash
# 安装依赖
sudo apt-get install -y g++-mingw-w64-i686 nasm pkg-config git

# 克隆 FFmpeg
git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git
cd FFmpeg

# 运行构建脚本
chmod +x /path/to/ci/build-libffmpeg-mingw32.sh
/path/to/ci/build-libffmpeg-mingw32.sh
```
