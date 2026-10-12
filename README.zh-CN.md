# QuotaBar 独立额度应用

独立运行的 macOS 菜单栏与悬浮额度应用。通过内嵌官方 Codex 0.144.1 运行时和隔离账户读取额度，不需要打开 Codex 桌面版或安装旧插件。

[最新发布与安装包](https://github.com/JaceHwang/codex-usage-sidebar/releases/latest) · [English](README.md) · [文档索引](docs/README.md)

## 功能

- 菜单栏：两行剩余额度和重置日期，或透明单色图标。设置中的“任务栏显示额度信息”控制两种模式，选择会保存。
- 悬浮按钮：默认开启，自由拖动并记住位置。菜单栏右键菜单的“显示悬浮按钮”独立控制显示，不在设置中。
- 原额度详情卡：悬停预览，点击固定，未锁定时再次点击收起；锁按钮控制保持打开，未锁定时外部点击收起。
- 原生设置：官方浏览器登录、登出、刷新、重新加载运行时、系统/浅色/深色主题、系统/简中/繁中/英文语言及登录启动。
- 安装迁移：旧名 Codex Quota.app 升级为 QuotaBar.app，保留账号和偏好，支持事务恢复、回退和卸载。

## 安装和重新开启

从同一 Release 下载 DMG、安装脚本、说明、来源记录及 SHA256 文件。发行文件仍名为 `codex-quota-vX.Y.Z-macos-arm64.dmg`，当前包内应用名为 **QuotaBar.app**。校验后，升级或迁移建议使用附带脚本：

```bash
python3 install-macos-standalone.py install --candidate '/Volumes/QuotaBar/QuotaBar.app'
```

安装器默认放在 **`~/Applications/QuotaBar.app`**。Finder 侧栏“应用程序”通常打开 `/Applications`，因此看不到用户级安装。退出后按 **⌘⇧G**，输入 `~/Applications`，双击 QuotaBar.app 即可重新开启；重复打开已运行的应用会显示设置。关闭设置继续常驻，退出或 ⌘Q 会清理内嵌采集进程。

声明支持 macOS 14+ Apple Silicon，已在 macOS 27.0 实测。安装包为本地签名，**未完成 Developer ID 公证**；首次打开可能需要在系统“隐私与安全性”批准。Windows 独立版尚未实施。周期额度不是 API 现金余额。

## 开发与验证

```bash
./governance doctor
./governance check all
CUS_RUNTIME_BINARY=/path/to/codex bash scripts/build-macos-standalone.sh
```

源码、资源和测试在 `native/`，安装、打包和来源验证工具在 `scripts/`。打包需要 Xcode 和固定官方 `codex-cli 0.144.1`；版本仅由 Release Please 管理，禁止覆盖已发布资产。

每次开发前读取[详细进度](docs/PROJECT_PROGRESS-standalone-app.md)并恢复看板，里程碑后更新。其他说明：[安装](docs/MACOS_STANDALONE.zh-CN.md)、[架构](docs/ARCHITECTURE.md)、[隐私](docs/PRIVACY.md)、[验收](docs/validation/macos-standalone.md)、[治理](docs/GOVERNANCE.md)。

当前源码已包含 QuotaBar 品牌和菜单栏/悬浮功能，公开 v0.5.1 仍使用旧名称，新 QuotaBar 版本正在发布准备中。历史代码及既有安装包保留在 Git 历史和 GitHub 历史发布中。
