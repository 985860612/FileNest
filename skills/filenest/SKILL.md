---
name: filenest
description: Use the local FileNest MCP server for native macOS archive, hash, image, PDF, spreadsheet, NCM, and OCR operations. Trigger when the user asks FileNest to process local files or explicitly requests the FileNest MCP.
---

# FileNest MCP

Use the connected FileNest MCP server for local file processing. If its tools are unavailable, stop and tell the user to configure `filenest-mcp`; do not silently replace it with Python, `7z`, or another implementation.

## Routing

- Archives: `archive_list`, `archive_create`, `archive_extract`.
- Hashes and catalogs: `hash_compute`, `catalog_export`.
- XLSX-driven file operations: `files_copy`, `files_rename`, `files_trash`.
- File cleanup: `file_extension_repair`, `file_regex_copy`, `file_sanitize_names`.
- Images and PDFs: `image_process`, `pdf_images_to_pdf`, `pdf_merge`, `pdf_split`, `pdf_extract_regex`, `pdf_signatures`.
- Spreadsheets and audio: `spreadsheet_group`, `ncm_convert`.
- Document recognition: `document_models_status`, `document_models_download`, `document_recognize`.

Choose document recognition mode from the requested outcome:

- `vision`: fast Apple Vision `accurate` text extraction without model downloads.
- `ocr`: PP-OCRv5 text detection and recognition; use when Paddle output compatibility matters.
- `structure`: PP-StructureV3 layout, reading order, and table structure.

## Operating rules

- Resolve inputs and outputs to explicit absolute paths before calling a tool.
- Inspect the tool schema when an argument or supported format is uncertain.
- Preserve source files unless the user explicitly requests an in-place or destructive operation.
- Pass `confirm=true` only after the user has authorized operations that rename, trash, repair, sanitize, or replace files.
- Never create RAR archives; FileNest supports RAR reading and extraction only.
- Report output paths and per-tool errors. When processing a batch, summarize successes and failures instead of hiding partial results.
