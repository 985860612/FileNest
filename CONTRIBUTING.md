# Contributing to FileNest / 参与 FileNest

Thanks for helping improve FileNest. 欢迎通过 Issue 和 Pull Request 改进文件台。

## Before you start / 开始之前

- Search existing issues before opening a new one. / 提交前请先搜索已有 Issue。
- Keep one pull request focused on one change. / 每个 PR 聚焦一项变更。
- Do not include private files, archives, credentials, or personal paths in test fixtures. / 测试数据不得包含隐私文件、凭证或个人路径。
- Changes to the 7-Zip bridge must preserve the third-party license notices. / 修改 7-Zip 桥接层时必须保留第三方许可声明。

## Build and test / 构建与测试

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -j 1
./scripts/build-engine.sh
./scripts/engine-smoke.sh
./scripts/build-app.sh
```

Use conventional commit subjects such as `feat:`, `fix:`, `docs:`, or `refactor:`. 请使用 conventional commits 格式。

## Pull requests / Pull Request

Describe the user-visible outcome, verification performed, and any licensing impact. UI changes should include a current macOS screenshot. 请说明用户可见结果、验证方式和许可影响；界面变更请附当前 macOS 截图。
