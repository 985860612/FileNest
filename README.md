# FileNest（文件台）

面向 macOS 的本地文件工作台，提供压缩解压、归档浏览、Excel 文件管理与 Hash 校验。应用直接加载 7-Zip SDK 26.02，通过 C ABI 在进程内执行归档操作，不启动 `7z`、`7zz` 或其他命令行子进程。

## 功能

- 创建 7z、ZIP 和 TAR 归档
- 解压 7z、ZIP、RAR、TAR、GZIP、BZIP2 和 XZ
- 文件与文件夹拖放、多选和批量解压
- 7z、ZIP 密码压缩及加密归档解压
- 7z 字典大小设置，以及 7z、ZIP、TAR 自定义大小分卷
- 解压前预览归档中的文件、目录和大小
- 压缩时默认排除 `.DS_Store`、`._*`、`__MACOSX` 等 macOS 元数据
- 本地计算和校验 MD5、SHA-1、SHA-256、SHA-512
- 实时进度、当前文件和任务取消
- Finder “快速操作/服务”菜单：解压到同名文件夹、压缩为 7z、压缩为 ZIP
- 扫描目录并导出原生 XLSX 文件目录清单
- 根据 XLSX 表头选择源/目标路径列，预览后批量复制文件
- 根据 XLSX 路径列批量把文件移到废纸篓（可恢复）
- Universal 2：同时支持 Apple silicon 和 Intel Mac
- 解压路径穿越防护，压缩文件通过 `.partial` 临时文件事务式生成

RAR 仅支持读取和解压，不支持创建。

分卷压缩会生成 `archive.7z.001`、`.002` 等连续文件。解压时选择 `.001`，应用会检查缺卷并在本机自动组合后解压；所有步骤仍在应用进程内完成。

## 构建

要求：macOS 13+、完整 Xcode、Swift 6、`curl`、`make`。

```bash
./scripts/build-app.sh
open "dist/文件台.app"
```

构建脚本会下载官方 7-Zip 26.02 源码包，校验 SHA-256，分别编译 arm64 与 x86_64 的全格式 `Format7zF` 动态库及桥接层，再组装并临时签名应用。第三方源码与构建产物只保存在 `.build/`，不会提交到仓库。

本机若安装了 `/Applications/Xcode-beta.app` 但未切换 `xcode-select`，脚本会自动通过 `DEVELOPER_DIR` 使用它。

## Finder 右键菜单

1. 把 `文件台.app` 移到 `/Applications`。
2. 启动一次应用。
3. 在 Finder 选择文件后打开右键菜单，在“快速操作”或“服务”中选择“文件台”操作。
4. 如果菜单未显示，到“系统设置 → 键盘 → 键盘快捷键 → 服务 → 文件与文件夹”启用对应项目。

Finder 服务默认使用无密码和标准压缩等级。需要密码或其他设置时使用主窗口。

## Excel 文件管理

从主窗口侧边栏的“Excel 文件管理”选择以下三种操作：

1. “导出目录”扫描指定目录，输出包含完整路径、所在目录、文件名、扩展名和大小的 `.xlsx`。
2. “批量复制”读取 `.xlsx` 第一张工作表，根据表头选择源文件列和目标文件列，先预览再执行。
3. “移到废纸篓”根据选中的路径列批量处理文件，执行前会再次确认，文件仍可从 macOS 废纸篓恢复。

XLSX 读写由 Foundation 处理 XML、由进程内 7-Zip SDK 处理 ZIP 容器，不依赖 Python、Pandas、Microsoft Excel，也不调用 `zip` / `unzip` 命令。

## 开发与验证

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
./scripts/build-engine.sh
./scripts/engine-smoke.sh
SEVENZIP_ENGINE_INTEGRATION=1 swift test
./scripts/build-app.sh
```

`engine-smoke.sh` 会通过桥接 ABI 执行真实的 7z 与 ZIP 压缩、内容列表和解压往返测试。

## 架构

```text
SwiftUI / AppKit / Finder Services
                ↓
        ArchiveEngine (Swift)
                ↓ dlopen + C ABI
   libsevenzipbridge.dylib (C++)
                ↓ 7-Zip COM interfaces
          7z.so (Format7zF)
```

## 隐私与安全

- 不联网、不上传文件、不采集遥测
- 不要求管理员权限
- 不调用 shell 或归档命令行程序
- 归档条目中的绝对路径和 `..` 父目录路径会被拒绝
- 输出归档只有完整成功后才从 `.partial` 改为最终文件名
- Finder 解压默认写入新的同名目录，避免覆盖旁边的已有文件

## 许可

FileNest 的 Swift 应用代码采用 MIT License。7-Zip 核心及派生桥接层遵循 GNU LGPL；RAR 解码代码还受 unRAR 限制。完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [`ThirdParty/7zip/`](ThirdParty/7zip/)。
