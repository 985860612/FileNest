# FileNest

English · [简体中文](README.md)

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-1d1d1f?logo=apple)](https://985860612.github.io/FileNest/en/)
[![Universal 2](https://img.shields.io/badge/Universal%202-Apple%20silicon%20%2B%20Intel-2867df)](https://github.com/985860612/FileNest/releases/latest)
[![MIT License](https://img.shields.io/badge/license-MIT-15845d)](LICENSE)

A native file workspace for macOS with archive creation, extraction and browsing, native PP-StructureV3 document recognition, local NCM audio recovery, Finder actions, Excel-based file management, and hash verification. Archive and recognition workloads run through in-process native SDKs without Python, `7z`, `7zz`, or other processing subprocesses.

[Product website](https://985860612.github.io/FileNest/en/) · [Download](https://github.com/985860612/FileNest/releases/latest) · [Report an issue](https://github.com/985860612/FileNest/issues)

![FileNest main window](docs/app-overview.webp)

## Highlights

- Create 7z, ZIP, and TAR; extract 7z, ZIP, RAR, TAR, GZIP, BZIP2, and XZ
- Configure passwords, compression level, 7z dictionary size, and custom 7z/ZIP/TAR volumes
- Open an archive without extracting it, then browse one directory level at a time with search and familiar file icons
- Finder actions for extraction, 7z/ZIP creation, and XLSX folder-inventory export
- Exclude `.DS_Store`, `._*`, `__MACOSX`, and related macOS metadata by default
- Compute and verify MD5, SHA-1, SHA-256, and SHA-512 locally
- Restore the original MP3/FLAC stream from NCM files locally and in batches, without uploads or re-encoding; preserve title, artist, album, and cover metadata
- Export XLSX inventories, batch-copy paths, or move matching files to the macOS Trash
- Detect and repair missing file extensions, copy by regular expression, and preview safe file/folder name cleanup
- Batch-compress and proportionally resize images, with JPEG, PNG, HEIC, and WebP conversion
- Convert images to PDF, merge sorted PDF/image folders, and split text PDFs by keyword
- Extract PDF text matches to XLSX and group, de-duplicate, and merge spreadsheet rows by a selected column
- Use the dedicated OCR entry to load only the two PP-OCRv5 detection/recognition models, skipping layout, reading order, tables, formulae, and charts
- Use the dedicated Apple Vision OCR entry for system-native `accurate` Chinese/English recognition with no model download
- Batch-recognize images and PDFs with native PP-StructureV3: PP-OCRv5, layout, reading order, orientation/unwarping, and wired/wireless tables; export JSON, Markdown, HTML, DOCX, or XLSX
- Reuse model sessions across a batch (default concurrency 2) and report total time, throughput, P50, and P95
- Include directories, parent folders, detected types, byte counts, and timestamps in catalog exports
- Live progress, current-file reporting, cancellation, path-traversal protection, and transactional archive output
- Universal 2 support for Apple silicon and Intel Macs

RAR is read-only. To extract a split archive, select its `.001` volume; FileNest checks for missing parts and combines them locally.

## Install

Download the Universal 2 archive from [Releases](https://github.com/985860612/FileNest/releases/latest), unzip it, and move `文件台.app` to `/Applications`.

This open-source build is not notarized. If Gatekeeper blocks the first launch, Control-click the app in Finder and choose **Open**.

## Finder actions

1. Move `文件台.app` to `/Applications` and launch it once.
2. Select files or folders in Finder and open **Quick Actions** or **Services**.
3. If the actions are hidden, enable the FileNest entries under **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders**.

Finder actions open dedicated task windows without flashing the main window. Compression parameters such as password, dictionary, and volume size are available in the dedicated archive window.

## Build

Requirements: macOS 13+, a full Xcode installation, Swift 6, `curl`, and `make`.

```bash
git clone https://github.com/985860612/FileNest.git
cd FileNest
./scripts/build-app.sh
open "dist/文件台.app"
```

The build downloads and verifies the official 7-Zip 26.02 and libwebp source archives, builds arm64 and x86_64 artifacts, then assembles a Universal 2 app plus portable `dist/cli/filenest-cli` and `dist/mcp/filenest-mcp` distributions with their runtime libraries.

## CLI / MCP interface

`filenest-cli` writes only the final JSON response to stdout. Model progress and errors are JSON on stderr. `filenest-mcp` is a native stdio JSON-RPC server with no Python or `7z` subprocess dependency.

```bash
dist/cli/filenest-cli version
dist/cli/filenest-cli tools
dist/cli/filenest-cli run hash_compute \
  --arguments '{"files":["/tmp/example.zip"],"algorithm":"SHA-256"}'
dist/cli/filenest-cli models status
dist/cli/filenest-cli models download
dist/cli/filenest-cli models download --ocr-only --model-size mobile
dist/cli/filenest-cli recognize --ocr-only --input ./scans --output ./ocr-results \
  --format markdown --model-size mobile --provider coreml
dist/cli/filenest-cli recognize --engine vision --input ./scans --output ./vision-results \
  --format markdown
dist/cli/filenest-cli recognize --input ./documents --output ./results \
  --format markdown --jobs 2
```

The MCP server exposes 22 tools spanning archives, hashes, XLSX catalogs and file operations, extension repair and regex copying, image processing, PDF conversion/merge/split/extraction/signatures, spreadsheet grouping, NCM recovery, and PP-StructureV3 models and recognition. Renaming, Trash operations, extension repair, name cleanup, and replacing original images require an explicit `confirm=true`.

Claude Desktop configuration after installing the app:

```json
{
  "mcpServers": {
    "filenest": {
      "command": "/Applications/文件台.app/Contents/MacOS/filenest-mcp"
    }
  }
}
```

Codex `~/.codex/config.toml` configuration:

```toml
[mcp_servers.filenest]
command = "/Applications/文件台.app/Contents/MacOS/filenest-mcp"
```

The command may instead point at the absolute path to `dist/mcp/filenest-mcp`; keep its sibling `Frameworks` directory with it. Call `tools/list` for complete self-describing input schemas.

### Import the FileNest Skill (optional)

The repository includes [`skills/filenest/SKILL.md`](skills/filenest/SKILL.md), which guides Claude and Codex to the appropriate FileNest MCP tool and distinguishes Apple Vision, PP-OCRv5, and PP-StructureV3. The Skill contains invocation guidance only; configure `filenest-mcp` above before using it.

Run the following commands from the repository root. Claude owns the installed source, while Codex uses a symlink to that same copy:

```bash
set -euo pipefail
mkdir -p "$HOME/.claude/skills" "$HOME/.codex/skills"
test ! -e "$HOME/.claude/skills/filenest" && test ! -L "$HOME/.claude/skills/filenest"
test ! -e "$HOME/.codex/skills/filenest" && test ! -L "$HOME/.codex/skills/filenest"
cp -R "$(pwd)/skills/filenest" "$HOME/.claude/skills/filenest"
ln -s "$HOME/.claude/skills/filenest" "$HOME/.codex/skills/filenest"
```

If either destination already exists, inspect its contents and `realpath` first instead of overwriting it. Verify the import with:

```bash
test -f "$HOME/.claude/skills/filenest/SKILL.md"
test -L "$HOME/.codex/skills/filenest"
test "$(realpath "$HOME/.claude/skills/filenest")" = \
  "$(realpath "$HOME/.codex/skills/filenest")"
```

Restart Claude or Codex, then ask it to use FileNest for a local task or invoke `$filenest` explicitly. For upgrades, compare the repository copy with the installed Claude source before replacing it; the Codex symlink does not need to be recreated.

Formats are `json|markdown|html|docx|xlsx`, and `--input` may be repeated. Select PP-StructureV3, PP-OCRv5, or Apple Vision with `--engine structure|paddle|vision`; `--ocr-only` remains an alias for Paddle. The 21 MiB Mobile and 165 MiB Server Paddle pairs support `--provider coreml|cpu`. Mobile CoreML uses the verified static-shape compatibility path to prevent corrupted dynamic-subgraph output. Vision is fixed to `accurate`, `zh-Hans + en-US`, and language correction, with no model download. MCP accepts `mode="structure"|"ocr"|"vision"`.

Steady-state results on the same 1656×1968 Chinese screenshot are below. Latency is the core recognition timer and peak RSS comes from `/usr/bin/time -l`.

| Model | Provider | Latency | Peak RSS | Result |
| --- | --- | ---: | ---: | --- |
| Mobile | CPU | 3.98 s | 385 MiB | all 31 lines, 948 characters |
| Mobile | CoreML compatibility | 3.47 s | 406 MiB | byte-identical to CPU |
| Server | CoreML | 3.39 s | 3.21 GiB | all 31 lines; only two bullet differences from CPU |
| Server | CPU | 8.62 s | 1.38 GiB | all 31 lines; accuracy baseline |
| Apple Vision | accurate | **0.77 s** | about 237 MiB | 29 natural lines, 1,018 characters |

With one session reused across five images, the Apple Vision accurate release build took **3.22 s (1.55 images/s, about 237 MiB)** with identical text hashes across all five outputs. Mobile + CPU took 16.24 s (639 MiB), Mobile + CoreML compatibility 16.15 s (643 MiB), Server + CoreML 15.18 s (3.71 GiB), and Server + CPU 43.35 s (2.11 GiB). Use Vision for fast text extraction, Paddle OCR for Paddle-model parity, and PP-StructureV3 for layout/table structure.

On this Mac, the first Vision accurate page from the newly built release binary took 30.13 s (32.52 s for five pages) while macOS prepared recognition resources. macOS caches that preparation; later launches and batches return to the steady-state figures above.

Full structure recognition remains on the verified Server + CPU path. Concurrency 2 is the balanced M-series default; concurrency 4 improves throughput with substantially higher peak memory.

The 11 checksum-pinned catalog models cover OCR, layout, reading order, orientation/unwarping, and wired/wireless tables. Separately licensed formula/chart generation files can be placed under `Formula/{encoder.onnx,decoder.onnx,tokenizer.json}` and `Chart/{encoder.onnx,decoder.onnx,prompt_ids.txt,tokenizer.json}` in the model directory. They are loaded lazily; pass `--charts` to enable chart generation.

## Develop and verify

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -j 1
./scripts/build-engine.sh
./scripts/engine-smoke.sh
SEVENZIP_ENGINE_INTEGRATION=1 swift test
./scripts/build-app.sh
```

Architecture: `SwiftUI / AppKit / filenest-cli / filenest-mcp → FileNestKit / FileNestOCRCore → Apple Vision / PaddleOCRCoreML / ONNX Runtime / 7-Zip SDK`.

## Privacy and security

- No network access except an explicit, checksum-verified model download; no file uploads, telemetry, or administrator privileges
- No shell or archive command-line invocation
- NCM conversion only restores audio already present in the source file; process files you are authorized to use
- Absolute and parent-directory archive paths are rejected
- Archive outputs move from `.partial` only after successful completion
- Finder extraction creates a new sibling folder by default to avoid overwriting existing files

Please report security issues privately as described in [SECURITY.md](SECURITY.md).

## Contributing and license

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow.

Original FileNest Swift application code is available under the [MIT License](LICENSE). The 7-Zip engine and derivative bridge follow the GNU LGPL, while RAR decoding is additionally subject to the unRAR restriction. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [`ThirdParty/7zip/`](ThirdParty/7zip/) for details.
