# FileNest（文件台）

[English](README.en.md) · 简体中文

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-1d1d1f?logo=apple)](https://985860612.github.io/FileNest/)
[![Universal 2](https://img.shields.io/badge/Universal%202-Apple%20silicon%20%2B%20Intel-2867df)](https://github.com/985860612/FileNest/releases/latest)
[![MIT License](https://img.shields.io/badge/license-MIT-15845d)](LICENSE)

面向 macOS 的原生文件工作台，提供压缩解压、归档浏览、PP-StructureV3 文档识别、NCM 音频恢复、Finder 右键操作、Excel 文件管理与 Hash 校验。归档与识别均由原生 SDK 在进程内完成，不启动 Python、`7z`、`7zz` 或其他处理子进程。

[产品官网](https://985860612.github.io/FileNest/) · [下载最新版](https://github.com/985860612/FileNest/releases/latest) · [反馈问题](https://github.com/985860612/FileNest/issues)

![FileNest 文件台主界面](docs/app-overview.webp)

## 主要功能

- 创建 7z、ZIP 和 TAR；解压 7z、ZIP、RAR、TAR、GZIP、BZIP2 和 XZ
- 支持密码、压缩等级、7z 字典大小和 7z/ZIP/TAR 自定义大小分卷
- 打开归档但不解压，按目录逐层浏览、搜索并显示常见文件类型图标
- Finder 快速操作：解压到同名文件夹、压缩为 7z/ZIP、导出文件夹 XLSX 清单
- 默认排除 `.DS_Store`、`._*`、`__MACOSX` 等 macOS 元数据
- 本地计算和校验 MD5、SHA-1、SHA-256、SHA-512
- 在本机批量恢复 NCM 中的原始 MP3/FLAC，不上传、不重新编码；支持标题、歌手、专辑和封面元数据
- 导出 XLSX 文件目录，并按 XLSX 路径列批量复制或移动到废纸篓
- 检测并修复缺失的文件扩展名，按正则批量复制，并预览清理文件与目录名称
- 批量压缩、等比例缩放图片并转换为 JPEG、PNG、HEIC 或 WebP
- 图片转 PDF；按自定义关键字排序合并 PDF/图片；按关键字拆分文字型 PDF
- 用正则批量提取 PDF 文本到 XLSX，并按指定 Excel 列分组、去重、合并
- 原生 PP-StructureV3 批量识别图片/PDF：PP-OCRv5、版面、阅读顺序、方向/矫正及有线/无线表格；导出 JSON、Markdown、HTML、DOCX、XLSX
- 共享模型会话与批量并发（默认 2）；界面显示总耗时、吞吐、P50/P95，模型下载后逐文件处理可离线完成
- 目录清单可包含目录、父目录、实际文件类型、字节数、创建时间和修改时间
- 实时进度、当前文件、任务取消、路径穿越防护和事务式归档输出
- Universal 2：同时支持 Apple silicon 和 Intel Mac

RAR 仅支持读取和解压，不支持创建。分卷归档解压时请选择 `.001`，FileNest 会检查缺卷并在本机组合后处理。

## 安装

从 [Releases](https://github.com/985860612/FileNest/releases/latest) 下载 Universal 2 压缩包，解压后把 `文件台.app` 移到 `/Applications`。

首次安装的未公证开发版本如被 Gatekeeper 阻止，可在 Finder 中右键应用并选择“打开”。

## Finder 右键菜单

1. 把 `文件台.app` 移到 `/Applications` 并启动一次。
2. 在 Finder 选择文件或文件夹，打开“快速操作”或“服务”。
3. 如果菜单未显示，到“系统设置 → 键盘 → 键盘快捷键 → 服务 → 文件与文件夹”启用 FileNest 操作。

快速操作会打开专用的压缩、解压或导出窗口，不会先闪现主窗口。需要密码、字典或分卷参数时可在专用压缩窗口中调整。

## 构建

要求：macOS 13+、完整 Xcode、Swift 6、`curl`、`make`。

```bash
git clone https://github.com/985860612/FileNest.git
cd FileNest
./scripts/build-app.sh
open "dist/文件台.app"
```

构建脚本下载官方 7-Zip 26.02 与 libwebp 源码包并校验 SHA-256，分别编译 arm64 与 x86_64 产物，再组装 Universal 2 应用、`dist/cli/filenest-cli` 和 ONNX Runtime，并临时签名。第三方源码与中间产物只保存在 `.build/`。

## CLI / MCP 接口

`filenest-cli` 的 stdout 只写最终 JSON，模型下载进度与错误以 JSON 写入 stderr，便于 MCP server 或其他自动化工具稳定调用。

```bash
dist/cli/filenest-cli version
dist/cli/filenest-cli models status
dist/cli/filenest-cli models download
dist/cli/filenest-cli recognize --input ./documents --output ./results \
  --format markdown --jobs 2
```

支持 `json|markdown|html|docx|xlsx`；可重复传入 `--input`。`--jobs 2` 是 M 系列 Mac 的推荐平衡配置，`--jobs 4` 吞吐更高但峰值内存明显增加。当前 server 模型固定走实测结果一致的 CPU 路径；CoreML 虽可能更快，但已发现识别结果缺失，故不作为可选项。

自动下载的 11 个校验模型覆盖 OCR、版面、阅读顺序、方向/矫正和有线/无线表格。公式与图表生成模型按上游许可单独提供时，可放到模型目录的 `Formula/{encoder.onnx,decoder.onnx,tokenizer.json}` 与 `Chart/{encoder.onnx,decoder.onnx,prompt_ids.txt,tokenizer.json}`；SDK 会惰性加载，CLI 用 `--charts` 开启图表生成。

## 开发与验证

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -j 1
./scripts/build-engine.sh
./scripts/engine-smoke.sh
SEVENZIP_ENGINE_INTEGRATION=1 swift test
./scripts/build-app.sh
```

架构：`SwiftUI / AppKit / filenest-cli → FileNestOCRCore / ArchiveEngine → PaddleOCRCoreML / ONNX Runtime / 7-Zip SDK`。

## 隐私与安全

- 除用户主动下载并校验识别模型外，不联网、不上传文件、不采集遥测，不要求管理员权限
- 不调用 shell 或归档命令行程序
- NCM 转换只恢复文件中已有的音频数据，请仅处理你有权使用的文件
- 拒绝归档条目中的绝对路径和 `..` 父目录路径
- 输出归档只有完整成功后才从 `.partial` 改为最终文件名
- Finder 解压默认写入新的同名目录，避免覆盖已有文件

安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。

## 贡献与许可

欢迎提交 Issue 和 Pull Request，开发流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

FileNest 的原创 Swift 应用代码采用 [MIT License](LICENSE)。7-Zip 核心及派生桥接层遵循 GNU LGPL；RAR 解码代码还受 unRAR 限制。完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [`ThirdParty/7zip/`](ThirdParty/7zip/)。
