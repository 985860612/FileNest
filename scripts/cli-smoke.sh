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
  *'"ok":true'*'"sdkVersion":"0.3.3"'*) ;;
  *) echo "Unexpected version response: $VERSION" >&2; exit 1 ;;
esac

HELP=$($CLI)
case "$HELP" in
  *'--engine structure|paddle|vision'*'--model-size mobile|server'*'--provider coreml|cpu'*'--ocr-only'*) ;;
  *) echo "OCR engine/model-size/provider options missing from CLI help" >&2; exit 1 ;;
esac

MODEL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/filenest-cli-models.XXXXXX")
trap 'rmdir "$MODEL_DIR" 2>/dev/null || true' EXIT
STATUS=$($CLI models status --model-dir "$MODEL_DIR")
case "$STATUS" in
  *'"ok":true'*'"ready":false'*) ;;
  *) echo "Unexpected model status response: $STATUS" >&2; exit 1 ;;
esac

OCR_STATUS=$($CLI models status --ocr-only --model-dir "$MODEL_DIR")
case "$OCR_STATUS" in
  *'"mode":"ocr"'*'"modelCount":2'*'"modelSize":"server"'*'"ok":true'*'"ready":false'*) ;;
  *) echo "Unexpected OCR-only model status response: $OCR_STATUS" >&2; exit 1 ;;
esac

MOBILE_OCR_STATUS=$($CLI models status --ocr-only --model-size mobile --model-dir "$MODEL_DIR")
case "$MOBILE_OCR_STATUS" in
  *'"mode":"ocr"'*'"modelCount":2'*'"modelSize":"mobile"'*'"ok":true'*'"ready":false'*) ;;
  *) echo "Unexpected Mobile OCR model status response: $MOBILE_OCR_STATUS" >&2; exit 1 ;;
esac

VISION_STATUS=$($CLI models status --engine vision --model-dir "$MODEL_DIR")
case "$VISION_STATUS" in
  *'"mode":"vision"'*'"modelCount":0'*'"modelSize":"system"'*'"ok":true'*'"ready":true'*) ;;
  *) echo "Unexpected Apple Vision status response: $VISION_STATUS" >&2; exit 1 ;;
esac

TOOLS=$($CLI tools)
case "$TOOLS" in
  *'"archive_create"'*'"image_process"'*'"pdf_signatures"'*) ;;
  *) echo "Unexpected tool inventory: $TOOLS" >&2; exit 1 ;;
esac

HASH_FILE="$MODEL_DIR/hash.txt"
printf 'hello' > "$HASH_FILE"
HASH=$($CLI run hash_compute --arguments "{\"files\":[\"$HASH_FILE\"],\"algorithm\":\"SHA-256\"}")
case "$HASH" in
  *'2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'*) ;;
  *) echo "Unexpected hash response: $HASH" >&2; exit 1 ;;
esac

echo "FileNest CLI JSON contract passed"
