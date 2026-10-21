# QuotaBar 独立额度应用

独立运行的 macOS/Windows 额度应用，提供菜单栏/托盘及悬浮入口。通过内嵌官方 Codex 0.144.1 运行时和隔离账户读取额度，不需要打开 Codex 桌面版或安装旧插件。

[最新发布 v0.7.0（Windows）](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.7.0) · [Windows安装包](https://github.com/JaceHwang/codex-usage-sidebar/releases/download/v0.7.0/QuotaBar-0.7.0-windows-x64.zip) · [Apple Silicon 安装包](https://github.com/JaceHwang/codex-usage-sidebar/releases/download/v0.6.0/codex-quota-v0.6.0-macos-arm64.dmg) · [English](README.md) · [文档索引](docs/README.md)

## 功能

- macOS菜单栏：两行剩余额度和重置日期，或透明单色图标。设置中的“任务栏显示额度信息”控制两种模式，选择会保存。
- 悬浮按钮：默认开启，自由拖动并记住位置。菜单栏右键菜单的“显示悬浮按钮”独立控制显示，不在设置中。 macOS当前本地开发候选在右侧增加悬停时显示的关闭按钮；关闭会保存隐藏状态，可由菜单栏右键重新开启。
- Windows托盘：所有主题固定圆形彩色图标；设置中的额度信息开关控制悬停提示。Windows正式版悬浮按钮已包含悬停关闭功能，可从托盘恢复。
- 原额度详情卡：悬停预览，点击固定，未锁定时再次点击收起；锁按钮控制保持打开，未锁定时外部点击收起。
- 原生设置：官方浏览器登录、登出、刷新、重新加载运行时、系统/浅色/深色主题、系统/简中/繁中/英文语言及登录启动。
- macOS安装迁移：旧名 Codex Quota.app 升级为 QuotaBar.app，保留账号和偏好，支持事务恢复、回退和卸载。

## macOS安装和重新开启

从同一 Release 下载 DMG、安装脚本、说明、来源记录及 SHA256 文件。发行文件仍名为 `codex-quota-vX.Y.Z-macos-arm64.dmg`，当前包内应用名为 **QuotaBar.app**。校验后，升级或迁移建议使用附带脚本：

```bash
python3 install-macos-standalone.py install --candidate '/Volumes/QuotaBar/QuotaBar.app'
```

安装器默认放在 **`~/Applications/QuotaBar.app`**。Finder 侧栏“应用程序”通常打开 `/Applications`，因此看不到用户级安装。退出后按 **⌘⇧G**，输入 `~/Applications`，双击 QuotaBar.app 即可重新开启；重复打开已运行的应用会显示设置。关闭设置继续常驻，退出或 ⌘Q 会清理内嵌采集进程。

声明支持 macOS 14+ Apple Silicon，已在 macOS 27.0 实测。安装包为本地签名，**未完成 Developer ID 公证**；首次打开可能需要在系统“隐私与安全性”批准。周期额度不是 API 现金余额。

## Windows安装和重新开启

Windows 11 x64 独立版已正式发布v0.7.0，全部功能及最新UI由用户验收，原生CI和公开下载包核验通过；托盘/程序统一圆形图标，额度放在提示及浮窗，见[Windows安装说明](docs/WINDOWS_STANDALONE.zh-CN.md)。

从同一发布下载ZIP和QUOTABAR-WINDOWS-SHA256SUMS.txt并校验，完整解压后运行 `QuotaBar/setup/QuotaBar.Setup.exe`。退出后从开始菜单搜索QuotaBar重开。Windows安装包未签名，升级和回退保留账号及设置。

## 开发与验证

macOS构建（需要Xcode）：

```bash
./governance doctor
./governance check all
CUS_RUNTIME_BINARY=/path/to/codex bash scripts/build-macos-standalone.sh
```

macOS源码、资源和测试在 `native/`，Windows实现和测试在 `windows/`，安装、打包和来源验证工具在 `scripts/`。macOS打包需要 Xcode 和固定官方 `codex-cli 0.144.1`；版本仅由 Release Please 管理，禁止覆盖已发布资产。

Windows构建需要.NET 10 SDK和Python，不需要Xcode：

```sh
dotnet run --project windows/QuotaBar.Core.Tests
python scripts/build-windows-standalone.py
```

正式发布额外在Windows执行原生启动退出和安装检查。

每次开发前读取[详细进度](docs/PROJECT_PROGRESS-standalone-app.md)并恢复看板，里程碑后更新。其他说明：[安装](docs/MACOS_STANDALONE.zh-CN.md)、[架构](docs/ARCHITECTURE.md)、[隐私](docs/PRIVACY.md)、[验收](docs/validation/macos-standalone.md)、[治理](docs/GOVERNANCE.md)。

Windows v0.7.0已发布，正式ZIP及四项辅助资产均已下载完整验证。macOS仍为v0.6.0，包含 QuotaBar 品牌和菜单栏/悬浮功能，五项公开资产已下载并完整验证。历史 v0.5.1 使用旧名称。历史代码及既有安装包保留在 Git 历史和 GitHub 历史发布中。

## 开发中的额度表情与提醒

当前源码新增四项独立可选功能：悬浮按钮电池表情、确认恢复提醒、局部小庆祝和 Bank 到期提醒（72／24 小时）。全部默认关闭，在“额度表情与提醒”设置中开启。小庆祝仅在悬浮按钮可见时播放；恢复需两次新鲜查询确认；Bank 日期缺失时不会猜测提醒，也不会自动兑换权益。

这是开发分支功能，不代表公开 v1.0.1 已包含。验证进度见[路线图](docs/PROJECT_PROGRESS-standalone-app.md)。
