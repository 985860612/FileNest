#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=26.02
ARCHIVE_NAME=7z2602-src.tar.xz
ARCHIVE_SHA256=cf967c98bca02a4b8b16375f441825a8e141362f14be1969bbec8e1ca0bff9dd
VENDOR_ROOT="$ROOT/.build/vendor"
SOURCE_ROOT="$VENDOR_ROOT/7zip-$VERSION"
DOWNLOAD_PATH="$VENDOR_ROOT/$ARCHIVE_NAME"
OUTPUT_ROOT="$ROOT/.build/engine"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

mkdir -p "$VENDOR_ROOT" "$OUTPUT_ROOT"

if [ ! -f "$DOWNLOAD_PATH" ]; then
  curl -L --fail --silent --show-error \
    "https://github.com/ip7z/7zip/releases/download/$VERSION/$ARCHIVE_NAME" \
    -o "$DOWNLOAD_PATH"
fi

ACTUAL_SHA256=$(shasum -a 256 "$DOWNLOAD_PATH" | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$ARCHIVE_SHA256" ]; then
  echo "7-Zip source checksum mismatch" >&2
  exit 1
fi

if [ ! -f "$SOURCE_ROOT/DOC/readme.txt" ]; then
  mkdir -p "$SOURCE_ROOT"
  tar -xJf "$DOWNLOAD_PATH" -C "$SOURCE_ROOT"
fi

CLIENT_DIR="$SOURCE_ROOT/CPP/7zip/UI/Client7z"
cp "$ROOT/Sources/SevenZipBridge/SevenZipBridge.cpp" "$CLIENT_DIR/SevenZipBridge.cpp"
cp "$ROOT/Sources/SevenZipBridge/include/SevenZipBridge.h" "$CLIENT_DIR/SevenZipBridge.h"
cp "$ROOT/Sources/SevenZipBridge/makefile.gcc" "$CLIENT_DIR/makefile.sevenzip-mac.gcc"
cp "$ROOT/Sources/SevenZipBridge/makefile.mac" "$CLIENT_DIR/makefile.sevenzip-mac.mac"
chmod u+w "$CLIENT_DIR/SevenZipBridge.cpp" "$CLIENT_DIR/SevenZipBridge.h" \
  "$CLIENT_DIR/makefile.sevenzip-mac.gcc" "$CLIENT_DIR/makefile.sevenzip-mac.mac"

build_arch() {
  local arch=$1
  local make_arch=$arch
  if [ "$arch" = x86_64 ]; then
    make_arch=x64
  fi
  local engine_object_dir="b/sevenzip_mac_${arch}"
  local bridge_object_dir="b/sevenzip_bridge_${arch}"

  make -C "$SOURCE_ROOT/CPP/7zip/Bundles/Format7zF" -j"$(sysctl -n hw.ncpu)" \
    -f "../../cmpl_mac_${make_arch}.mak" O="$engine_object_dir"
  make -C "$CLIENT_DIR" -j"$(sysctl -n hw.ncpu)" \
    -f makefile.sevenzip-mac.mac MAC_ARCH="$make_arch" O="$bridge_object_dir"

  cp "$SOURCE_ROOT/CPP/7zip/Bundles/Format7zF/$engine_object_dir/7z.so" \
    "$OUTPUT_ROOT/7z-$arch.so"
  cp "$CLIENT_DIR/$bridge_object_dir/libsevenzipbridge.so" \
    "$OUTPUT_ROOT/libsevenzipbridge-$arch.dylib"
}

build_arch arm64
build_arch x86_64

lipo -create "$OUTPUT_ROOT/7z-arm64.so" "$OUTPUT_ROOT/7z-x86_64.so" \
  -output "$OUTPUT_ROOT/7z.so"
lipo -create \
  "$OUTPUT_ROOT/libsevenzipbridge-arm64.dylib" \
  "$OUTPUT_ROOT/libsevenzipbridge-x86_64.dylib" \
  -output "$OUTPUT_ROOT/libsevenzipbridge.dylib"

install_name_tool -id @loader_path/libsevenzipbridge.dylib \
  "$OUTPUT_ROOT/libsevenzipbridge.dylib"

echo "$OUTPUT_ROOT"
