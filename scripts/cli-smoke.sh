#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI=${1:-"$ROOT/.build/debug/filenest-cli"}

if [ ! -x "$CLI" ]; then
  echo "CLI not executable: $CLI" >&2
  exit 1
fi

VERSION=$($CLI version)
case "$VERSION" in
  *'"ok":true'*'"sdkVersion":"0.3.0"'*) ;;
  *) echo "Unexpected version response: $VERSION" >&2; exit 1 ;;
esac

MODEL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/filenest-cli-models.XXXXXX")
trap 'rmdir "$MODEL_DIR" 2>/dev/null || true' EXIT
STATUS=$($CLI models status --model-dir "$MODEL_DIR")
case "$STATUS" in
  *'"ok":true'*'"ready":false'*) ;;
  *) echo "Unexpected model status response: $STATUS" >&2; exit 1 ;;
esac

echo "FileNest CLI JSON contract passed"
