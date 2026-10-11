# Codex Quota 独立额度应用

独立运行的 macOS 菜单栏应用，通过内嵌官方运行时和隔离账户读取额度，无需打开 Codex 桌面版，也不依赖插件界面。

[最新发布 v0.5.0](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.5.0) · [Apple Silicon 安装包](https://github.com/JaceHwang/codex-usage-sidebar/releases/download/v0.5.0/codex-quota-v0.5.0-macos-arm64.dmg)

菜单栏分两行显示剩余额度和重置日期，点击打开详情；设置支持登录、刷新、语言、主题和登录启动。账户凭据保存在本机隔离目录。周期额度不是现金余额。

当前公开安装包使用本地签名，未经过 Developer ID 公证。声明支持 macOS 14+ Apple Silicon，已实测 macOS 27.0；Windows 独立版仍在规划中。

- [安装和迁移](docs/MACOS_STANDALONE.zh-CN.md)
- [当前架构](docs/ARCHITECTURE.md)
- [开发进度](docs/PROJECT_PROGRESS-standalone-app.md)
- [验收记录](docs/validation/macos-standalone.md)

开发入口：`./governance doctor`、`./governance check all`。源码与测试统一位于 `native/`，构建、安装和发布工具位于 `scripts/`。版本仅由 Release Please 管理。旧插件源代码和旧安装包已移出本地工作区，可从 Git 历史及 GitHub 历史发布追溯。
