# Third-Party Notices

## 7-Zip 26.02

Copyright © 1999–2026 Igor Pavlov.

FileNest 构建并动态加载官方 7-Zip `Format7zF` 全格式模块。7-Zip 的大部分代码采用 GNU LGPL 2.1 或更高版本；部分 LZFSE、ZSTD 与 XXH64 文件采用 BSD 许可证；RAR 解码代码同时受 unRAR 限制。

FileNest 的 `SevenZipBridge.cpp` 以官方 `Client7z` 示例为基础修改，因此作为独立动态库按相同 LGPL 条款分发。应用与桥接库之间通过公开 C ABI 动态加载。

许可证原文：

- [`ThirdParty/7zip/License.txt`](ThirdParty/7zip/License.txt)
- [`ThirdParty/7zip/copying.txt`](ThirdParty/7zip/copying.txt)
- [`ThirdParty/7zip/unRarLicense.txt`](ThirdParty/7zip/unRarLicense.txt)

RAR 解码源码不得用于重新创建专有的 RAR 压缩算法。本项目不实现或提供 RAR 压缩。

## libwebp 1.6.0

Copyright © 2010 Google Inc.

FileNest 构建并动态加载官方 libwebp，在进程内编码 WebP 图片。libwebp 采用 BSD 3-Clause 风格许可证，并附带额外专利授权。

许可证原文：

- [`ThirdParty/webp/COPYING`](ThirdParty/webp/COPYING)
- [`ThirdParty/webp/PATENTS`](ThirdParty/webp/PATENTS)

## NCM interoperability reference

FileNest 的 NCM 互操作实现使用 macOS CommonCrypto，并由本项目以 Swift 独立实现；应用不捆绑或执行第三方 NCM 转换程序。

开发过程中参考了公开的 [`taurusxin/ncmdump`](https://github.com/taurusxin/ncmdump) 项目对 NCM 容器结构的说明。该项目声明采用 MIT License。此处保留引用和致谢，方便审查算法来源与互操作行为。
