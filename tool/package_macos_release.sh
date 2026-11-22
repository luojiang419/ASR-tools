#!/usr/bin/env bash
set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "该脚本仅用于 macOS。"
  exit 1
fi

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
PUBSPEC_FILE="$WORKDIR/pubspec.yaml"
BUILD_APP="$WORKDIR/build/macos/Build/Products/Release/asr_tools.app"
ENTITLEMENTS_FILE="$WORKDIR/macos/Runner/Release.entitlements"

VERSION="${1:-$(ruby -e 'puts File.read(ARGV[0])[/^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+$/, 1]' "$PUBSPEC_FILE")}"
if [[ -z "$VERSION" ]]; then
  echo "无法从 pubspec.yaml 解析版本号。"
  exit 1
fi

if [[ ! -d "$BUILD_APP" ]]; then
  echo "未找到构建产物: $BUILD_APP"
  exit 1
fi

FFMPEG_SOURCE_DIR="${ASR_TOOLS_FFMPEG_DIR:-/opt/homebrew/bin}"
INCLUDE_SHERPA="${ASR_TOOLS_INCLUDE_SHERPA:-0}"
SHERPA_SOURCE="${ASR_TOOLS_SHERPA_RUNTIME:-$HOME/Library/Application Support/asr_tools/runtime/sherpa-onnx}"

if [[ ! -x "$FFMPEG_SOURCE_DIR/ffmpeg" || ! -x "$FFMPEG_SOURCE_DIR/ffprobe" ]]; then
  echo "未找到 ffmpeg/ffprobe: $FFMPEG_SOURCE_DIR"
  exit 1
fi

DIST_DIR="$WORKDIR/dist/v$VERSION"
DIST_APP="$DIST_DIR/asr_tools.app"
DIST_ZIP="$DIST_DIR/asr_tools-macos-arm64.zip"
RUNTIME_ROOT="$DIST_APP/Contents/Resources/runtime"
SHERPA_DEST="$RUNTIME_ROOT/sherpa-onnx"
FFMPEG_DEST="$RUNTIME_ROOT/ffmpeg"

mkdir -p "$DIST_DIR"
rm -rf "$DIST_APP" "$DIST_ZIP"

echo "复制应用..."
ditto "$BUILD_APP" "$DIST_APP"

mkdir -p "$RUNTIME_ROOT"

if [[ "$INCLUDE_SHERPA" == "1" ]]; then
  if [[ ! -x "$SHERPA_SOURCE/bin/sherpa-onnx-offline" ]]; then
    echo "未找到 sherpa-onnx 运行时: $SHERPA_SOURCE"
    exit 1
  fi
  echo "嵌入 sherpa-onnx..."
  rm -rf "$SHERPA_DEST"
  ditto "$SHERPA_SOURCE" "$SHERPA_DEST"
  chmod +x "$SHERPA_DEST/bin/"*
else
  echo "跳过 sherpa-onnx 打包（当前阶段仅保留字幕合板所需 FFmpeg 运行时）"
  rm -rf "$SHERPA_DEST"
fi

echo "嵌入 ffmpeg..."
python3 "$WORKDIR/tool/bundle_macos_ffmpeg.py" "$FFMPEG_SOURCE_DIR" "$FFMPEG_DEST"

echo "签名嵌入运行时..."
while IFS= read -r -d '' file; do
  /usr/bin/codesign --force --sign - "$file"
done < <(
  find \
    "$RUNTIME_ROOT" \
    \( -path '*/bin/*' -o -path '*/lib/*.dylib' \) \
    -type f \
    -print0
)

echo "重新签名主应用并恢复 entitlements..."
/usr/bin/codesign \
  --force \
  --sign - \
  --entitlements "$ENTITLEMENTS_FILE" \
  "$DIST_APP"

echo "验证签名..."
/usr/bin/codesign --verify --deep --strict "$DIST_APP"
/usr/bin/codesign -d --entitlements :- "$DIST_APP" >/dev/null

echo "生成压缩包..."
ditto -c -k --sequesterRsrc --keepParent "$DIST_APP" "$DIST_ZIP"

echo
echo "输出目录: $DIST_DIR"
echo "应用包: $DIST_APP"
echo "压缩包: $DIST_ZIP"
if [[ "$INCLUDE_SHERPA" == "1" ]]; then
  echo "sherpa-onnx: $SHERPA_DEST"
else
  echo "sherpa-onnx: 未打包"
fi
echo "ffmpeg: $FFMPEG_DEST"
