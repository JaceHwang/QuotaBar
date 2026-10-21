# QuotaBar v1.1.0：额度表情与提醒

状态：2026-10-21双平台正式发布，公开下载与更新清单复核通过。[发布页](https://github.com/JaceHwang/QuotaBar/releases/tag/v1.1.0)。版本由Release Please PR #44生成；两端候选已获用户实机测试通过反馈。

## 更新内容

- 新增额度表情模式：悬浮电池角色展示充足、偏低、耗尽、不可用和恢复五种状态，角色增大至28pt/px，浮窗保持30pt/px高度。
- 新增额度恢复提醒：两次新鲜完整查询确认后通知，多个周期合并为一条；账户/套餐/周期变更重新建立基线，避免误报。
- 新增恢复小庆祝：紫色星星眼、举手与金色星光，区别于充足状态。恢复提醒或小庆祝任一开启，同次恢复只通知一次；隐藏浮窗不主动显示，减少动画时降级。
- 新增Bank到期提醒：提前72小时和24小时，根据已知可用权益合并、持久化去重；缺失日期不猜测，Bank保持只读。
- 四项默认开启，已保存的关闭选择保持，三语言与浅深色适配；macOS未决定通知权限时请求授权。
- 设置页采用侧栏分区、绿色开关、五状态图例及通知/Bank说明，保留账户、显示、更新和登录启动操作。
- 浮窗右键先隐藏详情，清除锁定/固定状态，菜单期间不重新弹出；移出再进入后恢复悬停。
- 修复仓库更名后的更新地址，改用 `https://jacehwang.github.io/QuotaBar/updates.json`，保留严格发布链接校验。旧版更新地址已失效，需手动安装本版恢复检查。
- 庆祝预览同步示例通知，不改变真实事件基线或Bank提醒记录；修复重复设置不同步、账户摘要过期及通知失败提示隐藏。

升级保留独立账户与设置。macOS Apple Silicon、Windows11 x64，共用官方Codex0.144.1内嵌运行时；不新增服务器、付费API或AI调用。macOS本地签名、未Developer ID公证，Windows未签名。

## 验证与发布记录

- 最终更新地址补丁：199项Swift测试、Windows14/14核心行为与协议/安装回归、10项清单测试及完整治理通过。功能源6614e9f的两轮原生CI与治理8项检查全部成功；版本PR原生CI39573032930及治理39573032869通过。
- 2026-10-21用户确认macOS与Windows实机测试通过，不推断未提供的逐项DPI/自然事件/VoiceOver/长期矩阵。
- 准确tag：`v1.1.0` → `6b511f4f83e244af43b842cab8ebe028af79a996`，共享version.txt与manifest均1.1.0；功能PR #43、版本PR #44已合并。
- [macOS发布39574187572](https://github.com/JaceHwang/QuotaBar/actions/runs/39574187572)与[Windows发布39574723747](https://github.com/JaceHwang/QuotaBar/actions/runs/39574723747)成功，两平台availability均available，10项正式资产公开。
- 公开DMG下载后通过摘要、严格签名、包内版本、完整源码快照/运行时及隔离构建目录后的真实启动退出验证。Windows公开ZIP通过完整载荷/PE x64、版本/源码/摘要、原生启动退出和安装升级回退卸载证明复核；此Mac主机未执行Windows程序。
- [Pages39575070102](https://github.com/JaceHwang/QuotaBar/actions/runs/39575070102)成功；[公网更新清单](https://jacehwang.github.io/QuotaBar/updates.json)已GET确认两端1.1.0、准确发布链接及摘要/更新说明。旧v1.0.1所有资产ID、大小、摘要不变。
- 公开包验证命令：`python3 scripts/verify-macos-standalone-release.py v1.1.0 <assets>`、`python3 scripts/verify-windows-standalone-release.py v1.1.0 <assets>`，均在准确tag HEAD运行且成功。本次公开包隔离启动不改变用户已安装候选或账户。
