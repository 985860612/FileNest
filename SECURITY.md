# Security Policy / 安全策略

## Supported version / 支持版本

Security fixes target the latest release of FileNest. 安全修复面向 FileNest 最新发布版本。

## Reporting a vulnerability / 报告漏洞

Please do not publish exploitable details in a public Issue. Use GitHub's **Report a vulnerability** private advisory form for this repository. 请勿在公开 Issue 中披露可利用细节，请使用本仓库 GitHub Security 页面中的 **Report a vulnerability** 私密报告入口。

Include the affected version, archive format or workflow, reproduction steps, observed impact, and a minimal non-sensitive sample when possible. 如条件允许，请提供受影响版本、归档格式或操作路径、复现步骤、影响以及不含隐私的最小样本。

You should receive an initial response within seven days. 收到报告后，维护者会尽量在七天内首次回复。

## Scope / 范围

Path traversal, unintended overwrite, malformed archive crashes, password leakage, code execution, Finder Service privilege issues, and dependency integrity problems are in scope. UI-only defects and unsupported archive formats should use the public issue tracker. 路径穿越、意外覆盖、畸形归档崩溃、密码泄露、代码执行、Finder 服务权限问题和依赖完整性属于安全范围；纯界面问题与不支持格式请提交公开 Issue。
