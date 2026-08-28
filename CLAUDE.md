# CLAUDE.md — SevenZip Mac

原生 macOS 压缩与解压工具。压缩内核必须通过进程内 7-Zip SDK 调用，不得启动 `7z`、`7zz` 或其他命令行子进程。

## 技术约束

- Swift 6、SwiftUI + AppKit，macOS 13+
- 7-Zip C++ 源码经稳定 C ABI 暴露给 Swift
- Finder 操作与主窗口共用 `ArchiveCore`
- RAR 仅支持读取和解压，不提供压缩
- 归档文件路径必须经过路径穿越检查
- 不提交 `.build/`、`dist/` 和第三方源码构建产物
- 发布包必须包含 7-Zip 与 RAR 解码相关许可证声明

## 验证要求

- `swift build`
- 7z、ZIP 压缩与解压往返烟测
- 错误密码、取消任务、同名输出路径和路径穿越测试
- `./scripts/build-app.sh` 能生成可启动的 `.app`
