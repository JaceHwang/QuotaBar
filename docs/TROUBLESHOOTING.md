# QuotaBar troubleshooting

Updated: 2026-10-12.

| Symptom | Check or action |
| --- | --- |
| Missing in Finder Applications | Installer uses `~/Applications`, while the sidebar usually opens `/Applications`. Command + Shift + G → `~/Applications` → QuotaBar.app. |
| Reopen after Quit | Double-click QuotaBar.app; opening an already running app shows settings. Closing settings keeps the app running. |
| Menu bar shows only an icon | Enable Settings → “Show quota information in menu bar” to restore two quota/date lines. Icon mode is a transparent system-tinted symbol. |
| Floating button absent | Right-click the menu bar item → enable “Show floating button”. This option is no longer in settings. |
| Button position unsuitable | Drag it. Position persists; removed-display recovery clamps it into a visible work area. Full multi-display unplug acceptance remains pending. |
| Details remain open | Unlock the pin button. Clicking a pinned floating button again dismisses it until the pointer exits; unlocked outside clicks dismiss it. |
| No quota | Complete official login in settings, then refresh. The isolated account can differ from the desktop account. |
| Offline/stale quota | Check connectivity, refresh or reload runtime. A cached percentage does not prove a successful current query. |
| First launch blocked | Packages are locally signed, not Developer ID notarized. Inspect source/signature and allow through macOS Privacy & Security if appropriate. |
| Duplicate old name | Use the transaction installer. It detects Codex Quota.app and migrates to QuotaBar.app. If both active paths exist, resolve the duplicate before installing; do not delete account data. |
| Interrupted rename/update | Rerun the installer; its journal restores the original path first. Rollback/uninstall then uses the recovered active path. |
| Login startup unavailable | Check macOS Login Items approval. Settings reflects actual Service Management status, not just a saved toggle. |
| Runtime process remains after Quit | Report version and reproduction; app and bundled runtime should exit together. Closing settings is not Quit. |
| Build license download fails | Retry packaging after connectivity recovers. Do not bypass source/runtime/signature verification. |

Include app version, macOS version/architecture and reproduction. Omit credentials, personal account details and unrelated screenshots. See [installation](MACOS_STANDALONE.zh-CN.md) and [validation](validation/macos-standalone.md).

## Quota moods and reminders

All four controls default on under Quota moods and reminders; saved off choices remain off. macOS requests notification permission if undecided and either reminder is enabled; denied permission must be changed in system settings. A mood is based on unrounded usage; displayed 0% can mean a fraction remains. Gray/question-mark means data is unavailable or stale, not depleted. Recovery takes a second fresh read (15–120 seconds) to confirm; a countdown reaching zero alone never notifies. A still-depleted second window remains a limit.

Enable system notifications for QuotaBar and check OS Focus/Do Not Disturb if a test message is not visible. Preview celebration works only while the floating indicator is already visible. Bank reminders require known available credits with a future expiry, and only notify at the current 72/24-hour stage. Missing/cached Bank details never trigger alerts. A write failure suppresses alerts until local state can be saved; do not delete the isolated account folder to reset a notification.

## 角色气泡提醒（开发分支，尚未发布）

- 在“额度表情与管理 → 提醒展示方式”选择悬浮气泡、系统通知、两者或关闭。各类已有开关仍需开启；升级保留原关闭、跳过版本和稍后提醒记录。
- 气泡不要求系统通知权限。系统／两者模式被系统拒绝时，检查系统通知设置；两者模式的气泡仍可工作。
- 浮窗隐藏、锁屏、休眠、拖动、右键菜单或额度详情展开时不主动冒泡；从菜单／托盘或设置打开“未读提醒”。记录仅本次运行，最多32条，非活跃记录保留24小时，不是完整历史。所有气泡在额度不变时持续显示，新的完整查询确认原始使用率变化后收起；活跃气泡不按24小时清理，仍可主动关闭。旧Bank记录会标为历史，不宣称权益仍可用。
- 可“暂停气泡1小时”，重启保留暂停截止时间；系统免打扰不自动控制应用内气泡。
- “预览气泡”是主动示例展示，可在暂停或关闭自动提醒时测试；请先显示浮窗并收起详情。它不会重置真实去重记录。
- “知道了”只处理本条消息，不等于关闭浮窗、跳过版本或兑换Bank。“查看Bank”只打开详情；更新入口仍打开已验证的发布页，不自动安装。
