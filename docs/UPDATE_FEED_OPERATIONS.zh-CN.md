# 更新清单运维与验收

当前代码已实现；Pages 尚未部署。用户要求暂不发布产品，远程启用是后续独立动作。

## 客户端行为

- 两端使用 https://jacehwang.github.io/codex-usage-sidebar/updates.json 。只识别本平台稳定版本，数字比较，不接受草稿、预发布或降级。
- 自动检查默认开；首次延迟约30秒，成功后每6小时加抖动。系统提醒默认关，开启后 macOS 请求系统授权。手动检查有10秒节流。
- 未部署/断网/限流/无效数据时显示检查失败，额度查询继续运行。已发现的合法更新可以继续查看。
- 查看更新打开 GitHub 发布页；没有自动下载或自动安装。稍后提醒24小时，跳过仅影响该版本。
- Windows NotifyIcon 提醒以 BalloonTipShown 作为已显示依据；被系统抑制时保留重试资格，每30分钟最多尝试一次。macOS 被拒绝权限时保留应用内入口。

## 首次启用顺序（需要确认后执行）

1. 合并并确保默认分支包含更新清单生成器和 update-feed.yml；该功能 draft PR #36 依赖 macOS Tibo draft PR #35。
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
