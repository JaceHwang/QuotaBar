# QuotaBar macOS v0.6.0

[发布页](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.6.0) · [DMG](https://github.com/JaceHwang/codex-usage-sidebar/releases/download/v0.6.0/codex-quota-v0.6.0-macos-arm64.dmg)

日期：2026-10-12。精确 tag commit：`b308da8f7d26b3d6f6728f82977e3ded025fa10b`。功能/文档 PR #29 和 Release Please PR #30 全部 CI 通过后合并。

## 交付

QuotaBar 名称及正式应用图标；默认开启的自由拖动悬浮额度按钮；原详情的悬停、点击、固定及锁定；菜单栏右键“显示悬浮按钮”；设置中的“任务栏显示额度信息”在双行额度日期和透明单色图标间切换。状态和位置分别保存，旧名 Codex Quota.app 事务升级保留账户与偏好，恢复后回退/卸载重新定位活动路径。

五项资产：`codex-quota-v0.6.0-macos-arm64.dmg`、`CODEX-QUOTA-PROVENANCE.json`、`CODEX-QUOTA-SHA256SUMS.txt`、`CODEX-QUOTA-INSTALL.zh-CN.md`、`install-macos-standalone.py`。附带官方 Codex 0.144.1，安装器默认 `~/Applications/QuotaBar.app`；Finder 侧栏通常为 `/Applications`。重开方法见[安装说明](../MACOS_STANDALONE.zh-CN.md)。

## 验证

158 Swift 测试及 10 安装/迁移测试通过。精确 tag 构建与验包、公开下载件的 SHA256、DMG、图标元数据、严格签名、运行时/应用摘要和 tag 源码快照全部通过。GitHub latest 确认为 v0.6.0，draft=false，prerelease=false，五项资产完整。正式 0.6.0 已安装到本机，官方登录有效、真实额度和详情显示、登录启动状态正常；未复制桌面账户。

Apple Silicon，声明 macOS 14+，本机 macOS 27.0。本地签名，未 Developer ID 公证。右键悬浮项经源码审查但未自动点击；完整系统主题、最低系统、多屏拔插、休眠和长期矩阵未完成。Windows 独立版尚未实施。
