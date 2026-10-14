# 更新清单运维与验收

Pages 更新清单已于2026-10-14依用户授权启用并部署，公网入口为 https://jacehwang.github.io/codex-usage-sidebar/updates.json 。本次仅上线静态清单，未发布新版产品。

## 客户端行为

- 两端使用 https://jacehwang.github.io/codex-usage-sidebar/updates.json 。只识别本平台稳定版本，数字比较，不接受草稿、预发布或降级。
- 自动检查默认开；每次启动延迟约30秒检查一次，不因上次成功时间跳过；成功后每24小时检查。失败保留短间隔指数退避（5、10、20分钟等），避免重复请求。系统提醒默认关，开启后 macOS 请求系统授权。手动检查有10秒节流。
- 未部署/断网/限流/无效数据时显示检查失败，额度查询继续运行。已发现的合法更新可以继续查看。
- 查看更新打开 GitHub 发布页；没有自动下载或自动安装。稍后提醒24小时，跳过仅影响该版本。
- Windows NotifyIcon 提醒以 BalloonTipShown 作为已显示依据；被系统抑制时保留重试资格，每30分钟最多尝试一次。macOS 被拒绝权限时保留应用内入口。

## 首次启用顺序（已执行，供维护参考）

1. 确保默认分支包含生成器和 update-feed.yml；#35/#36已合并，#38也已为本次完整更新说明部署合并为f321da6。
2. 确认项目 GitHub Pages 无其他站点需保留；将发布来源设为 GitHub Actions，核对 github-pages 环境允许默认分支部署。
3. 将仓库变量 QUOTABAR_UPDATE_FEED_ENABLED 设为 true。当前默认未启用，普通分支推送不会部署。
4. 手动运行 Publish update feed。构建器从公开 Releases 检索平台完整资产，核对摘要、来源与 Windows 原生验证记录；成功后部署静态清单。
5. 从公开 HTTPS 入口下载 JSON，确认 schemaVersion=1，以及 macos-arm64/windows-x64 分别指向实际已发布的有效版本，链接无404且平台版本不串。
6. 分别验证两端手动检查、权限拒绝、重复检查/重启、稍后/跳过及通知点击。系统权限和Focus/勿扰影响实际提醒，需记录设备结果。

首次清单应反映现有正式包：macOS 0.6.0，Windows 0.7.0；本机 macOS 0.7.0 开发候选不应收到0.6.0降级提醒。更新功能自身需候选安装或后续正式版本安装后才具备检查能力，既有旧应用不会自动获得该功能。

## 后续平台发布

Publish release platform 成功结束后，Publish update feed 自动运行（显式启用变量为true时）。同一并发组串行，不取消正在部署的任务；重新读取完整公开 releases，分别选择各平台最高有效版本。网络或证据失败时构建失败，保留上一份已部署清单，修复后可手动重试。

不上传或覆盖已发布版本的资产。生成器不执行发布包代码，也不读取 PR/触发工作流的构建产物；只执行默认分支受控脚本，并从公开发布读取有界 metadata。客户端没有 GitHub token，也不向清单服务发送账号或额度数据。

## 本地检查

- python3 scripts/test-update-feed.py
- python3 scripts/generate-update-feed.py --output .dist/update-site/updates.json（需要已配置的 gh 读取公开发布）
- ./governance check all（完整 Swift/Core/安装事务及 Windows 编译）
- Windows 原生：dotnet run --project windows/QuotaBar.Windows.Tests --configuration Release

通知权限的真实 OS 对话框、勿扰抑制、退出/重新启动点击行为和签名身份升级必须用实际安装件检查，mock网络与截图不能代替。
# 更新内容字段

平台条目可包含可选 `summary`（系统提醒摘要）和 `releaseNotes`（应用内完整纯文本说明）。生成器从该平台已验证的公开 Release 正文生成：摘要优先取前三条列表项，正文转为纯文本，链接保留标题，移除 HTML 标签和 Markdown 标记。摘要最多 240 个字符、正文最多 16000 个字符，不加载外部 HTML。

维护者在 Release 正文写清用户可读的变更。平台错位发布时，各平台使用自身对应版本的正文；显示发布者原文，不自动翻译。清单仍为 schemaVersion 1，旧客户端忽略新增字段，新客户端兼容缺少字段的旧清单。空内容沿用原提醒文案和发布页入口。全文显示于现有可滚动设置，系统提醒可能按可用空间截断摘要。

本功能不会自动开启 Pages 或发布产品，继续遵循独立授权边界。

## macOS 原生启动证明门禁

macOS v1.0.0公开包实机发现资源加载崩溃，已保留资产并在发布页标注。静态签名、摘要与来源验证不能代替实际启动；今后生成器只推荐外部PROVENANCE中`nativeMacOSStartupExit=true`的macOS发布包。旧包缺少该证明时不再被推荐，没有合格macOS条目时可省略该平台，Windows条目独立保持有效；客户端将缺少本平台条目视为无可用更新。网络或证据读取失败仍使构建失败，不替换已部署清单。

构建器复制安装后的App到独立临时目录，使用隔离用户目录启动，隐藏SwiftPM构建目录，验证真实官方运行时到达待登录状态及正常退出、子进程清理后记录证明；发布验证器再次执行此测试。隐藏构建目录防止CI机器上的绝对路径掩盖安装件缺少资源的问题。修复资产必须使用新版本，不能覆盖已公开文件。

## 首次部署证据（2026-10-14）

用户明确要求启动部署Pages。原站点不存在，已创建GitHub Actions发布模式并启用HTTPS；github-pages环境允许main分支，QUOTABAR_UPDATE_FEED_ENABLED=true。工作流38441971437成功完成构建及部署，来源f321da6。

公网JSON成功读取且与本地已验证生成结果一致：schemaVersion=1，macOS 0.6.0、Windows 0.7.0，各自含summary/releaseNotes。本机已安装0.7.0开发候选手动检查从失败恢复为“未发现更新版本”，符合不降级规则。真实新版本通知投递、Windows用户设备联网检查未在本轮验收。Release Please #37保持未合并，没有新安装包发布或已发布资产覆盖。

两平台发布页与下载URL的公网HEAD检查均返回200。初次下载链接检查出现瞬时TLS连接失败，保留证书验证，以HTTP/1.1有界重试后通过。

