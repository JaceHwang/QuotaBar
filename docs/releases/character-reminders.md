# v1.3.0 角色提醒、Bark手机推送与设置统一发布

状态：2026-10-23双端正式发布并完成公开下载、来源、SHA256及更新清单复核。[发布页](https://github.com/JaceHwang/QuotaBar/releases/tag/v1.3.0)。

## 内容

- C角色对白气泡统一恢复、Bank和更新提醒；全部气泡在额度未变化时保留，可主动关闭。
- Bark独立手机通道、系统安全保存Key、事件持久去重和显式示例测试。
- 关于应用最后页签、更新与项目链接、待上线官网；手机推送Key显隐与三步图文向导。
- 侧栏/关于复用详情圆环，全部设置操作按钮统一获取Bark样式。

## 发布前证据

产品77f37ef的CI39912641396与39912637030、治理均成功，Mac158Core+107AppKit、Windows原生WPF/三语言/DPI、候选来源、官方运行时启动及安装/升级/回滚/卸载均验证。Windows实际截图已检查；Mac本机77f37ef候选经用户钥匙串授权后正常显示，旧版备份与配置保留。

本版本未新增Windows用户设备/自然恢复事件/真实手机送达/全部DPI多屏长期矩阵证明。最终版本资产仅从准确tag构建，禁止覆盖已有同名资产；安装及故障限制沿用平台文档。

## 正式产物

- 完整功能整合：[PR54](https://github.com/JaceHwang/QuotaBar/pull/54)，全部8项检查通过后squash合并e2026e5。原串联PR51-53已关闭为完成整合，不删除开发分支。
- Release Please生成[PR55](https://github.com/JaceHwang/QuotaBar/pull/55)，仅同步manifest、version.txt和CHANGELOG为1.3.0；准确head60fe0c0的[原生CI39932467472](https://github.com/JaceHwang/QuotaBar/actions/runs/39932467472)及治理全部成功。
- 准确tag `v1.3.0` → `40909c95023c560d8345385428f96d42ff40dfb9`，由[Release Please39933147828](https://github.com/JaceHwang/QuotaBar/actions/runs/39933147828)创建。
- [Windows发布39933265991](https://github.com/JaceHwang/QuotaBar/actions/runs/39933265991)与[macOS发布39933271404](https://github.com/JaceHwang/QuotaBar/actions/runs/39933271404)成功，均准确tag原生构建校验后上传，无覆盖既有资产。
- 10项公开资产：macOS DMG、安装脚本/说明、来源与校验和；Windows ZIP、安装说明、来源、原生验证记录及校验和。Release非草稿、非预发布，两端availability均available，GitHub latest指向v1.3.0。
- 从公开发布下载全部10文件，大小与SHA256逐项匹配GitHub元数据；v1.2.0全部10资产的ID/大小/摘要与发布前一致。
- 在准确tag HEAD执行 `python3 scripts/verify-windows-standalone-release.py v1.3.0 .dist/release-download/v1.3.0` 和 `python3 scripts/verify-macos-standalone-release.py v1.3.0 .dist/release-download/v1.3.0` 均通过。Windows核对PE x64、完整文件、来源指纹、运行时和ZIP；Mac核对签名、DMG、源码/运行时摘要及隔离实际启动/退出。
- [更新清单Pages39933807848](https://github.com/JaceHwang/QuotaBar/actions/runs/39933807848)完成；[公网GET](https://jacehwang.github.io/QuotaBar/updates.json)确认两端1.3.0、准确下载链接、非空摘要及完整发布说明。
- 本地完整治理158Core+107AppKit及Windows检查通过。安装包及原始下载仅保存在被忽略的.dist目录，不提交二进制。
