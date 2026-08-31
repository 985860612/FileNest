#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MCP=${1:-"$ROOT/.build/debug/filenest-mcp"}

if [ ! -x "$MCP" ]; then
  echo "MCP server not executable: $MCP" >&2
  exit 1
fi

RESPONSES=$(
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"file_sanitize_names","arguments":{"root":"/tmp"}}}' \
  | "$MCP"
)

LINE_COUNT=$(printf '%s\n' "$RESPONSES" | wc -l | tr -d ' ')
if [ "$LINE_COUNT" -ne 3 ]; then
  echo "Expected 3 JSON-RPC responses, got $LINE_COUNT" >&2
  exit 1
fi

for expected in '"name":"filenest-mcp"' '"version":"0.3.5"' '"name":"archive_create"' '"name":"document_recognize"' '"enum":["structure","ocr","vision"]' '"enum":["coreml","cpu"]' '"enum":["mobile","server"]' '"isError":true' 'confirm=true'; do
  case "$RESPONSES" in
    *"$expected"*) ;;
    *) echo "Missing MCP response fragment: $expected" >&2; exit 1 ;;
  esac
done

echo "FileNest MCP initialize, inventory and confirmation guard passed"
