# macOS 独立额度应用使用说明

这是独立菜单栏应用，正式发布状态以 GitHub Release 为准。当前安装包使用本地签名，未经过 Developer ID 公证。声明最低 macOS 14、Apple Silicon；本次实机验证环境为 macOS 27.0 arm64。Windows 路线另见开发进度文档。

## 使用

应用安装在用户目录 `~/Applications/Codex Quota.app`。启动后常驻菜单栏，分两行显示周期剩余比例和重置日期；点击显示原额度详情卡，右键提供刷新、设置和退出。双击已运行的应用可打开设置。关闭设置窗口继续常驻；退出或 Cmd-Q 会清理内嵌采集子进程。

设置支持 OpenAI 官方浏览器登录、取消、登出、刷新、重新加载运行时、系统/浅色/深色主题、系统/简中/繁中/英文语言和可选登录启动。系统要求批准登录启动时，按设置窗口提示操作。后台约一分钟查询，失败退避最长约五分钟；休眠暂停，唤醒及网络恢复尝试刷新。服务端提供的额度与重置时间为准；Token 不用于估算额度或现金余额。

账户保留在 `~/Library/Application Support/CodexUsageSidebar/CodexHome`，由官方运行时管理凭据。独立账户可以与 Codex 桌面版不同。应用不复制桌面版凭据，不需要 Codex 插件或预装 CLI。详情卡使用 AppKit 鼠标事件来关闭外部点击，未安装键盘全局监控或扫描宿主窗口；[Apple 事件监控文档](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)说明了键盘事件的辅助功能权限限制。

## 下载与安装

从对应 GitHub Release 下载 `codex-quota-vX.Y.Z-macos-arm64.dmg`，用同页 `CODEX-QUOTA-SHA256SUMS.txt` 校验。打开 DMG，将 `Codex Quota.app` 复制到用户的 Applications 文件夹后启动。应用内已包含官方运行时，不需要预装 Codex CLI。

已安装旧插件或希望保留可恢复升级记录时，建议下载同页 `install-macos-standalone.py`，在装有 Python 3 的终端运行以下命令，路径替换为 DMG 中应用的实际路径：

```bash
python3 install-macos-standalone.py install --candidate '/Volumes/Codex Quota/Codex Quota.app'
```

此方式负责停用旧入口并保留备份。手动复制应用不会自动迁移旧插件；迁移前应停止旧插件以免重复常驻。首次打开若被 macOS 拦截，需要由用户在系统“隐私与安全性”中检查并允许该应用；未公证包没有自动通过 Gatekeeper 的保证。

## 构建与可恢复安装

在仓库根目录执行：

```bash
bash scripts/build-macos-standalone.sh
python3 scripts/install-macos-standalone.py install --candidate '/完整路径/Codex Quota.app'
```

构建要求本机 Xcode、Apple Silicon 和固定官方 CLI `codex-cli 0.144.1`，也可用 `CUS_RUNTIME_BINARY` 指向已验证的同版本程序。产物包含 app、DMG、许可、来源及源码快照、校验摘要，安装后的应用只使用自身内嵌运行时。

安装器默认停用旧插件 enabled flag 和 LaunchAgent，并停止旧 companion；只修改目标插件的 flag，不删除插件缓存或覆盖整个 Codex 配置。私有备份与恢复日志保存在数据根目录的 `.StandaloneBackups` 及 `standalone-*.json`。安装中断后再次执行安装器会先恢复未完成事务。

```bash
python3 scripts/install-macos-standalone.py rollback
python3 scripts/install-macos-standalone.py uninstall
python3 scripts/install-macos-standalone.py restore-legacy
```

`rollback` 回到前一独立候选，保留账户。`uninstall` 注销登录启动并把应用移入恢复备份，保留账户；旧插件继续停用。`restore-legacy` 显式停止独立版并恢复已备份的旧入口。卸载不删除凭据；需要清除登录时先在应用中登出，不直接删除整个历史数据根目录。

## 当前边界

本地签名和 DMG 校验通过，不等于 Developer ID 公证通过。发布版本仅由 Release Please 生成，正式资产从对应版本 tag 构建。Developer ID 公证、干净设备、最低支持系统和长期兼容矩阵尚未完整验收。无多账号同时监控、历史趋势、自动更新安装或自动兑换 Bank。

详细状态和待验证项见[开发进度](PROJECT_PROGRESS-standalone-app.md)及[实机验收记录](validation/macos-standalone.md)。
