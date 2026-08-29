#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENGINE_ROOT="$ROOT/.build/engine"
SMOKE_ROOT=$(mktemp -d)
trap 'rm -rf "$SMOKE_ROOT"' EXIT

if [ ! -f "$ENGINE_ROOT/libsevenzipbridge.dylib" ]; then
  "$ROOT/scripts/build-engine.sh" >/dev/null
fi

mkdir -p "$SMOKE_ROOT/input/nested"
printf 'FileNest SDK smoke test\n' > "$SMOKE_ROOT/input/fixture.txt"
printf 'nested content\n' > "$SMOKE_ROOT/input/nested/inside.txt"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

xcrun clang -Wall -Wextra -Werror \
  -I"$ROOT/Sources/SevenZipBridge/include" \
  "$ROOT/Tests/BridgeSmoke/main.c" -o "$SMOKE_ROOT/bridge-smoke"

for format in 7z zip; do
  SMOKE_PASSWORD='correct-horse-battery-staple' "$SMOKE_ROOT/bridge-smoke" \
    "$ENGINE_ROOT/libsevenzipbridge.dylib" \
    "$ENGINE_ROOT/7z.so" \
    "$SMOKE_ROOT/input" \
    "$SMOKE_ROOT/archive.$format" \
    "$SMOKE_ROOT/output-$format" \
    "$format"
  cmp "$SMOKE_ROOT/input/fixture.txt" \
    "$SMOKE_ROOT/output-$format/input/fixture.txt"
  cmp "$SMOKE_ROOT/input/nested/inside.txt" \
    "$SMOKE_ROOT/output-$format/input/nested/inside.txt"
done

echo "7z and ZIP SDK round trips passed"
