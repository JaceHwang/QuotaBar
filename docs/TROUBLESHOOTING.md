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
