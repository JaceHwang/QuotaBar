# QuotaBar v1.2.0：设置与悬浮显示优化

状态：2026-10-22双平台正式发布，公开下载和更新清单核验通过。[发布页](https://github.com/JaceHwang/QuotaBar/releases/tag/v1.2.0)。用户明确授权推送、合并和发布，并反馈实机测试通过。

## 更新内容

- 四个设置页统一分组、右侧原生开关、圆角按钮和间距，保持B方向侧栏与电池角色。
- 账户操作按登录状态显示，运行时重载放入故障排查；显示页拆分外观与常驻行为。
- 表情页移除重复设置与预览入口，更新页强化版本、进度和操作层次。
- 修复悬浮额度重置时间末位数字被裁切、Windows辅助技术切换后偏好未保存，以及切换语言后状态提示未更新。
- 保留独立账户、已保存偏好及提醒检测去重规则；四功能默认开启，既有关闭选择不变。Bank只读，无新增服务或API调用。

macOS Apple Silicon与Windows x64继续内嵌官方Codex0.144.1。macOS本地签名、未Developer ID公证，Windows未签名。

## 验证与发布证据

- 功能PR [#46](https://github.com/JaceHwang/QuotaBar/pull/46)与安装指南PR [#48](https://github.com/JaceHwang/QuotaBar/pull/48)已合并；准确功能提交38ce4ec和指南168da51各8项原生CI/治理检查成功。
- Release Please重新生成版本PR [#49](https://github.com/JaceHwang/QuotaBar/pull/49)，准确head87d01d9的[原生CI39751460486](https://github.com/JaceHwang/QuotaBar/actions/runs/39751460486)与[治理39751460343](https://github.com/JaceHwang/QuotaBar/actions/runs/39751460343)全部成功。旧PR47的GitHub自动合并标题超过72字符导致治理失败，已关闭并保留记录；没有绕过门禁或人工修改版本。
- 准确tag：`v1.2.0` → `eae7c1cc69dbeaa37aee9e447059be56d639a1c3`；共享version.txt和manifest为1.2.0，由[Release Please39752079744](https://github.com/JaceHwang/QuotaBar/actions/runs/39752079744)生成。
- [macOS发布39752176428](https://github.com/JaceHwang/QuotaBar/actions/runs/39752176428)与[Windows发布39752647890](https://github.com/JaceHwang/QuotaBar/actions/runs/39752647890)成功，10项资产全部公开，两端availability均available。
- 公开DMG重新下载后通过SHA256、严格签名、版本、准确tag源码快照、内嵌运行时，以及隐藏构建目录后的隔离账户真实启动退出。Windows公开ZIP通过完整文件、PE x64、来源、摘要及原生CI启动退出/安装升级回退卸载证明核验；本Mac主机没有执行Windows程序。
- [Pages39753040666](https://github.com/JaceHwang/QuotaBar/actions/runs/39753040666)成功；[公网更新清单](https://jacehwang.github.io/QuotaBar/updates.json)GET确认两端1.2.0、准确发布链接及非空摘要/更新说明。全部10文件大小和SHA256与GitHub资产元数据一致，v1.1.0全部资产ID/大小/摘要保持不变。
- 复核命令：`python3 scripts/verify-macos-standalone-release.py v1.2.0 <assets>`、`python3 scripts/verify-windows-standalone-release.py v1.2.0 <assets>`，均在准确tag HEAD成功。日志与公开文件保存在本机`.dist/release-download/v1.2.0`及临时发布验证日志中，不提交安装包或私人账户数据。


用户实机通过反馈单独记录；没有逐项提供的DPI、多屏、最低系统、读屏器和长期运行矩阵不视作全部通过。公开包在隔离目录验证，不改变用户本机账户或已安装候选。
