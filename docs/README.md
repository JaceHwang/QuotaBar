# QuotaBar 文档索引

当前产品为双平台独立额度应用：macOS（native/）、Windows（windows/）共用统一版本。v1.3.0已发布角色对白气泡、独立Bark手机推送和五页统一设置；两端原生CI、Windows截图、公开资产与更新清单已核验。新功能Windows用户设备矩阵仍待验证，详情见发布记录。文档更新日期：2026-10-23。

| 文档 | 用途 |
| --- | --- |
| [安装和使用](MACOS_STANDALONE.zh-CN.md) | 下载校验、用户级安装、重开、菜单栏/浮窗及回退卸载 |
| [Windows安装与验收](WINDOWS_STANDALONE.zh-CN.md) | 独立托盘/浮窗、每用户安装、重开及Windows验收步骤 |
| [架构](ARCHITECTURE.md) | 官方运行时、UI、状态、位置和账户边界 |
| [隐私](PRIVACY.md) | 凭据、数据、偏好和诊断 |
| [故障处理](TROUBLESHOOTING.md) | 找不到应用、显示模式、登录、更新和退出 |
| [仓库治理](GOVERNANCE.md) | 开发分支、检查、Release Please 和资产验证 |
| [开发进度](PROJECT_PROGRESS-standalone-app.md) | 双平台全周期路线、当前功能详细基线、Windows W0–W6迁移/验收指南和里程碑证据 |
| [设置优化验收](validation/2026-10-22-settings-ui-polish.md) | 2026-10-22四页设置布局、原生开关、UIA/语言回归与本机候选证据 |
| [额度体验验收](validation/quota-experiences.md) | 四功能、B界面、默认值、两端候选与用户设备反馈 |
| [v1.1.0 发布记录](releases/quota-experiences-v1.1.0.md) | 本轮统一版本更新内容、准确tag与正式资产验收状态 |
| [macOS 验收](validation/macos-standalone.md) | 本地/CI/设备/发布证据与未验证矩阵 |
| [Windows v0.7.0 记录](releases/windows-standalone-v0.7.0.md) | 首个Windows独立版、圆形图标与详情优化、准确tag及公开资产验证 |
| [v0.6.0 记录](releases/macos-standalone-v0.6.0.md) | QuotaBar 品牌、悬浮控制及菜单栏显示正式发行 |
| [v0.5.0 记录](releases/macos-standalone-v0.5.0.md) | 旧名称首个独立版的历史发布事实 |
| [v0.5.1 记录](releases/macos-standalone-v0.5.1.md) | 清理重构版的历史发布事实 |

历史文档标明当时版本，不将新功能回写成旧版本已拥有。发布结果以 [GitHub Releases](https://github.com/JaceHwang/QuotaBar/releases/latest) 为准；待发布内容与已经发布的安装包分别记录。

- [v1.2.0发布记录](releases/settings-ui-v1.2.0.md)：准确tag、原生构建、公开下载及更新清单核验。

- [C 方案设置页验收](validation/2026-10-23-settings-about-bark-guide.md)：关于应用最后页签、Key 显隐及原生连接向导。
- [Bark 手机推送配置](BARK_MOBILE_PUSH.zh-CN.md)：手机推送页、Key 安全保存、独立通道、测试与去重。
- [Bark 实施计划](superpowers/plans/2026-10-23-bark-mobile-push.md)与[验收记录](validation/2026-10-23-bark-mobile-push.md)：两端实现、自动化、CI及设备边界。

- [C参考图气泡验收](validation/2026-10-23-character-bubble-reference.md)：左侧独立角色、对白卡、紧凑排版及两端验证。

- [角色提醒与手机推送发布](releases/character-reminders.md)：本轮授权、双端来源、原生验证及正式资产进度。
