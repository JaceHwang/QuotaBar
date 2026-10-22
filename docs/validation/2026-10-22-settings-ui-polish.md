# 设置界面优化验收记录

日期：2026-10-22（Asia/Shanghai）。用户批准文字提案后实施；没有生成新的效果图。

## 范围与实现证据

| 提案要求 | 实现及证据 |
| --- | --- |
| 保留B侧栏和电池角色 | macOS QuotaSettingsShellView与WPF SettingsWindow保留四页导航；独立图标/文字区域，短英文导航保留完整页面标题 |
| 统一设置行/尾列控件 | macOS QuotaSettingsStyle.row，原生NSSwitch；Windows SettingsVisual.Toggle/Row，固定尾列、可换行标题、UIA标签 |
| 合理窗口与正文宽度 | macOS900×650、最小840×560、正文≤640；Windows920×710外框、最小宽840、短屏最小高受工作区约束；大窗口不拉满正文 |
| 账户身份与操作层级 | 身份/套餐（仅有可靠字段时）/状态分层；登录与取消/退出按状态显示，额度详情与刷新独立，重载放在故障排查折叠区域 |
| 显示分组 | 外观（主题/语言）和常驻入口；macOS菜单栏、Windows托盘分别用词；每个设置只有一个可编辑入口 |
| 额度页面 | 四个开关，五个紧凑图例、单一庆祝预览、单一测试通知、72/24小时辅助说明、持久化失败/通知不可用提示及系统设置入口 |
| 更新页面 | 版本/结果卡片、就近检查动作、进度指示、两个开关；有更新才显示发行说明和操作；语言切换不保留旧语言状态 |
| 视觉细节 | 弱描边与组内分隔；系统圆角按钮；Windows细滚动条与深浅色；保留原账户隔离、默认值、事件引擎、系统通知和庆祝语义 |

## 自动化验证

- `./governance doctor`：hooks active，独立仓库治理检查通过。
- 完整 `PATH="$DOTNET_ROOT:$PATH" DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./governance check all`：Swift145Core＋62AppKit，共207项；Windows14/14核心行为、协议/认证隔离、安装事务回归；Windows主程序/安装器/UI测试交叉构建零警告。最终本地日志：`/tmp/quotabar-settings-visual-final-governance.log`，退出0。
- 初始新布局回归在原实现出现14次预期失败：跨页重复、两个预览、开关在左侧、正文无限拉宽及账户操作状态。
- `SettingsPolishTests`：三语言×两主题×四页原生渲染24份；900及840pt控制边界、1400pt正文限宽，最小窗口滚动至最后控件；唯一设置归属、单预览、账户状态、辅助技术触发偏好保存、切换语言重建权限提示。
- macOS按AppKit alignment rect检查布局，避免将文本绘制/焦点扩展误认成内容裁切；初始document使用有效宽度消除约束冲突。旧独立更新测试host扩大以容纳分组布局，真实短窗口由集成滚动回归覆盖。
- Windows原生测试增加CheckBoxAutomationPeer.Toggle实际调用、状态重建/本地化、测试入口唯一、三语言深浅色四页截图、最小窗口与末项完整可见。曾在CI39720726035（da0a99e）实际失败“accessibility toggle persists preference”；确认UIA修改Checked不会触发鼠标Click后，改为Checked/Unchecked保存，CI39721106873（2dc2319）已全程通过。
- 独立只读审查发现的通知失败提示重建丢失/缺少系统设置入口P2已修复并复核关闭。后续原生测试发现的UIA保存问题及跨语言提示已另行修复；未删测试或放宽检查以回避真实失败。

## CI与截图

- CI39720041411（07be76b）：双端原生UI、打包、运行时启动退出及Windows实际安装/升级/回退/卸载通过。
- CI39721106873（2dc2319）：同上通过，包含UIA修复与状态本地化。下载Windows截图已检查；版本裁切、长条按钮、旧语言错误提示均已消除。
- 最后两处Windows视觉调整1cc9971（账户图标及6px滚动条）对应CI39721503294：两端全程成功；治理39721503231通过，PR46准确源码HEAD1cc9971全部4项检查成功。最后Windows截图已下载复核。
- macOS渲染：`/tmp/quotabar-settings-polish/`；Windows截图：`.dist/settings-polish-windows-1cc9971-ui/`。截图使用示例数据，窗口外的黑色透明区域不是产品背景；Windows测试宿主默认程序集版本1.0.0并非候选产品版本。

## 本机安装

- 候选：`.dist/standalone-macos/candidate-20261022-121349/`，来源2dc2319、clean、local-development-candidate；产品版本保持Release Please管理的1.1.0。
- 构建、深度严格签名、DMG校验、隐藏构建目录后的隔离账户/官方运行时启动退出全部通过。首次打包因GitHub SSL连接中断，重试后通过，未弱化SSL或签名验证。
- 事务安装到`~/Applications/QuotaBar.app`，保留账户、设置、登录启动与可恢复备份。PID69467：phase=ready、has_quota=true；startup-status=1；应用/运行时摘要匹配候选。
- 安装包SOURCE-SNAPSHOT的84个原生源码/测试/构建文件逐项与最后Windows视觉提交后的工作区摘要一致，确认后续Windows专属补丁未遗漏Mac功能。
- 通过真实本机菜单进入设置并切换显示/额度/更新页；AX树确认四项开关值1、正确switch角色与标签、五状态说明、唯一预览及通知设置入口；滚动条可到达底部。检查更新实际返回“未发现更新版本”。

## 边界与交付

- Draft PR： https://github.com/JaceHwang/QuotaBar/pull/46 。不合并，不公开发布，不改版本号或覆盖v1.1.0资产。
- Windows结果是原生CI及渲染证据，不声称本次有新的用户Windows设备验收。
- 未逐项执行VoiceOver/Narrator实际语音、完整键盘导航/所有OS全键盘访问设置、Windows全部DPI/多屏、最低系统、长时间运行，以及真实权限拒绝后打开系统设置的完整人工流程。辅助技术API触发与标签已自动化验证，不代替全部读屏器实机矩阵。
- 自然额度恢复及真实Bank临期未重新遇到；本次没有改变事件检测，预览不作为真实事件证据。

## 正式发布补充（2026-10-22）

用户随后反馈实机通过并明确授权推送、合并、发布。PR46已合并，v1.2.0已由Release Please生成并完成两端发布；以上Draft及不公开发布的记录属于早期交付阶段，当前以[发布记录](../releases/settings-ui-v1.2.0.md)为准。用户反馈不替代未提供的逐项设备矩阵。
