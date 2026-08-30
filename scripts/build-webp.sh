#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=1.6.0
ARCHIVE_NAME="libwebp-$VERSION.tar.gz"
ARCHIVE_SHA256=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
VENDOR_ROOT="$ROOT/.build/vendor"
SOURCE_ROOT="$VENDOR_ROOT/libwebp-$VERSION"
DOWNLOAD_PATH="$VENDOR_ROOT/$ARCHIVE_NAME"
BUILD_ROOT="$ROOT/.build/webp-build"
OUTPUT_ROOT="$ROOT/.build/webp"

mkdir -p "$VENDOR_ROOT" "$OUTPUT_ROOT"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
elif [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [ ! -f "$DOWNLOAD_PATH" ]; then
  curl -L --fail --silent --show-error \
    "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/$ARCHIVE_NAME" \
    -o "$DOWNLOAD_PATH"
fi

ACTUAL_SHA256=$(shasum -a 256 "$DOWNLOAD_PATH" | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$ARCHIVE_SHA256" ]; then
  echo "libwebp source checksum mismatch" >&2
  exit 1
fi

if [ ! -f "$SOURCE_ROOT/CMakeLists.txt" ]; then
  tar -xzf "$DOWNLOAD_PATH" -C "$VENDOR_ROOT"
fi

build_arch() {
  local arch="$1"
  local arch_build_root="$BUILD_ROOT/$arch"
  local arch_output="$OUTPUT_ROOT/libwebp-$arch.dylib"

  cmake -S "$SOURCE_ROOT" -B "$arch_build_root" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$(xcrun --find clang)" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_SHARED_LIBS=ON \
    -DWEBP_BUILD_ANIM_UTILS=OFF \
    -DWEBP_BUILD_CWEBP=OFF \
    -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF \
    -DWEBP_BUILD_IMG2WEBP=OFF \
    -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF \
    -DWEBP_BUILD_LIBWEBPMUX=OFF \
    -DWEBP_BUILD_WEBPMUX=OFF \
    -DWEBP_BUILD_EXTRAS=OFF >/dev/null

  cmake --build "$arch_build_root" --target webp --parallel "$(sysctl -n hw.ncpu)" >/dev/null
  cp "$arch_build_root/libwebp.dylib" "$arch_output"
  cp -L "$arch_build_root/libsharpyuv.0.dylib" "$OUTPUT_ROOT/libsharpyuv-$arch.dylib"
}

build_arch arm64
build_arch x86_64

lipo -create \
  "$OUTPUT_ROOT/libwebp-arm64.dylib" \
  "$OUTPUT_ROOT/libwebp-x86_64.dylib" \
  -output "$OUTPUT_ROOT/libwebp.dylib"
lipo -create \
  "$OUTPUT_ROOT/libsharpyuv-arm64.dylib" \
  "$OUTPUT_ROOT/libsharpyuv-x86_64.dylib" \
  -output "$OUTPUT_ROOT/libsharpyuv.0.dylib"
install_name_tool -id @loader_path/libwebp.dylib "$OUTPUT_ROOT/libwebp.dylib"
install_name_tool -change \
  @rpath/libsharpyuv.0.dylib \
  @loader_path/libsharpyuv.0.dylib \
  "$OUTPUT_ROOT/libwebp.dylib"
install_name_tool -id @loader_path/libsharpyuv.0.dylib "$OUTPUT_ROOT/libsharpyuv.0.dylib"

file "$OUTPUT_ROOT/libwebp.dylib" | grep -q 'universal binary'
file "$OUTPUT_ROOT/libsharpyuv.0.dylib" | grep -q 'universal binary'
echo "$OUTPUT_ROOT/libwebp.dylib"
