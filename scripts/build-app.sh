#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/文件台.app"
CLI_DIST="$ROOT/dist/cli"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

"$ROOT/scripts/build-engine.sh" >/dev/null
"$ROOT/scripts/build-webp.sh" >/dev/null
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --show-bin-path --arch arm64 --arch x86_64)

mkdir -p "$ROOT/dist" "$ROOT/.build/icon"
rm -rf "$APP" "$CLI_DIST" "$ROOT/.build/icon/AppIcon.iconset"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
mkdir -p "$CLI_DIST/licenses" "$APP/Contents/Resources/ocr-licenses"

cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN_DIR/SevenZipMac" "$APP/Contents/MacOS/SevenZipMac"
cp "$BIN_DIR/filenest-cli" "$APP/Contents/MacOS/filenest-cli"
cp "$BIN_DIR/filenest-cli" "$CLI_DIST/filenest-cli"
cp "$ROOT/.build/engine/7z.so" "$APP/Contents/Frameworks/7z.so"
cp "$ROOT/.build/engine/libsevenzipbridge.dylib" \
  "$APP/Contents/Frameworks/libsevenzipbridge.dylib"
cp "$ROOT/.build/webp/libwebp.dylib" "$APP/Contents/Frameworks/libwebp.dylib"
cp "$ROOT/.build/webp/libsharpyuv.0.dylib" \
  "$APP/Contents/Frameworks/libsharpyuv.0.dylib"
if [ -d "$BIN_DIR/onnxruntime.framework" ]; then
  cp -R "$BIN_DIR/onnxruntime.framework" "$APP/Contents/Frameworks/onnxruntime.framework"
  cp -R "$BIN_DIR/onnxruntime.framework" "$CLI_DIST/onnxruntime.framework"
fi
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp -R "$ROOT/ThirdParty/7zip" "$APP/Contents/Resources/7zip-licenses"
cp -R "$ROOT/ThirdParty/webp" "$APP/Contents/Resources/webp-licenses"
cp "$ROOT/.build/checkouts/PaddleOCRCoreML/LICENSE" \
  "$APP/Contents/Resources/ocr-licenses/PaddleOCRCoreML-LICENSE"
cp "$ROOT/.build/artifacts/paddleocrcoreml/onnxruntime/LICENSE" \
  "$APP/Contents/Resources/ocr-licenses/ONNXRuntime-LICENSE"
cp "$ROOT/.build/checkouts/PaddleOCRCoreML/LICENSE" \
  "$CLI_DIST/licenses/PaddleOCRCoreML-LICENSE"
cp "$ROOT/.build/artifacts/paddleocrcoreml/onnxruntime/LICENSE" \
  "$CLI_DIST/licenses/ONNXRuntime-LICENSE"

xcrun swift "$ROOT/scripts/generate-icon.swift" "$ROOT/.build/icon/AppIcon.iconset"
iconutil -c icns "$ROOT/.build/icon/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
codesign --force --deep --sign - "$CLI_DIST/filenest-cli"
echo "$APP"
echo "$CLI_DIST/filenest-cli"
