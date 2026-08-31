#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/文件台.app"
CLI_DIST="$ROOT/dist/cli"
MCP_DIST="$ROOT/dist/mcp"
PADDLEOCR_SDK_ROOT=${PADDLEOCR_COREML_LOCAL_PATH:-"$ROOT/.build/checkouts/PaddleOCRCoreML"}

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

"$ROOT/scripts/build-engine.sh" >/dev/null
"$ROOT/scripts/build-webp.sh" >/dev/null
mkdir -p "$ROOT/dist" "$ROOT/.build/icon"
rm -rf "$APP" "$CLI_DIST" "$MCP_DIST" "$ROOT/.build/icon/AppIcon.iconset"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --show-bin-path --arch arm64 --arch x86_64)

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
mkdir -p "$CLI_DIST/Frameworks" "$CLI_DIST/licenses" "$MCP_DIST/Frameworks" "$MCP_DIST/licenses" "$APP/Contents/Resources/ocr-licenses"

cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN_DIR/SevenZipMac" "$APP/Contents/MacOS/SevenZipMac"
cp "$BIN_DIR/filenest-cli" "$APP/Contents/MacOS/filenest-cli"
cp "$BIN_DIR/filenest-mcp" "$APP/Contents/MacOS/filenest-mcp"
cp "$BIN_DIR/filenest-cli" "$CLI_DIST/filenest-cli"
cp "$BIN_DIR/filenest-mcp" "$MCP_DIST/filenest-mcp"
cp "$ROOT/.build/engine/7z.so" "$APP/Contents/Frameworks/7z.so"
cp "$ROOT/.build/engine/libsevenzipbridge.dylib" \
  "$APP/Contents/Frameworks/libsevenzipbridge.dylib"
cp "$ROOT/.build/webp/libwebp.dylib" "$APP/Contents/Frameworks/libwebp.dylib"
cp "$ROOT/.build/webp/libsharpyuv.0.dylib" \
  "$APP/Contents/Frameworks/libsharpyuv.0.dylib"
for portable_dir in "$CLI_DIST" "$MCP_DIST"; do
  cp "$ROOT/.build/engine/7z.so" "$portable_dir/Frameworks/7z.so"
  cp "$ROOT/.build/engine/libsevenzipbridge.dylib" "$portable_dir/Frameworks/libsevenzipbridge.dylib"
  cp "$ROOT/.build/webp/libwebp.dylib" "$portable_dir/Frameworks/libwebp.dylib"
  cp "$ROOT/.build/webp/libsharpyuv.0.dylib" "$portable_dir/Frameworks/libsharpyuv.0.dylib"
done
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp -R "$ROOT/ThirdParty/7zip" "$APP/Contents/Resources/7zip-licenses"
cp -R "$ROOT/ThirdParty/webp" "$APP/Contents/Resources/webp-licenses"
cp "$PADDLEOCR_SDK_ROOT/LICENSE" \
  "$APP/Contents/Resources/ocr-licenses/PaddleOCRCoreML-LICENSE"
cp "$ROOT/.build/artifacts/paddleocrcoreml/onnxruntime/LICENSE" \
  "$APP/Contents/Resources/ocr-licenses/ONNXRuntime-LICENSE"
cp "$PADDLEOCR_SDK_ROOT/LICENSE" \
  "$CLI_DIST/licenses/PaddleOCRCoreML-LICENSE"
cp "$ROOT/.build/artifacts/paddleocrcoreml/onnxruntime/LICENSE" \
  "$CLI_DIST/licenses/ONNXRuntime-LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$CLI_DIST/licenses/THIRD_PARTY_NOTICES.md"
cp -R "$ROOT/ThirdParty/7zip" "$CLI_DIST/licenses/7zip"
cp -R "$ROOT/ThirdParty/webp" "$CLI_DIST/licenses/webp"
cp -R "$CLI_DIST/licenses/." "$MCP_DIST/licenses/"

xcrun swift "$ROOT/scripts/generate-icon.swift" "$ROOT/.build/icon/AppIcon.iconset"
iconutil -c icns "$ROOT/.build/icon/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
for portable_dir in "$CLI_DIST" "$MCP_DIST"; do
  codesign --force --sign - "$portable_dir/Frameworks/7z.so"
  codesign --force --sign - "$portable_dir/Frameworks/libsevenzipbridge.dylib"
  codesign --force --sign - "$portable_dir/Frameworks/libwebp.dylib"
  codesign --force --sign - "$portable_dir/Frameworks/libsharpyuv.0.dylib"
done
codesign --force --sign - "$CLI_DIST/filenest-cli"
codesign --force --sign - "$MCP_DIST/filenest-mcp"
echo "$APP"
echo "$CLI_DIST/filenest-cli"
echo "$MCP_DIST/filenest-mcp"
