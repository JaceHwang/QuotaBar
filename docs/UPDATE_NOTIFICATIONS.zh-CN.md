# QuotaBar 跨平台更新通知方案

分析日期：2026-10-13（Asia/Shanghai）。本文件是建议方案，未授权实现、服务部署或发布。

## 现状和结论

macOS 是 Swift/AppKit 菜单栏常驻程序，Windows 是 .NET 10 WPF＋WinForms NotifyIcon，当前没有远程更新检查器或系统更新通知适配器。macOS 已有 checkForUpdates 本地化文案，不代表功能已实现。两端已有网络恢复、唤醒与额度刷新机制，应新增独立更新检查状态，避免共用额度刷新周期。

实际公开资产：GitHub latest v0.7.0 只有 Windows x64 包，macOS 正式包仍在 v0.6.0。本机 macOS v0.7.0 是开发候选。因此必须按平台、架构、渠道和正式资产可用性查询，不能只看全局 latest，不能把未发布候选或草稿作为更新，也不能向候选推荐旧版。

推荐先实现远程版本清单＋客户端定时检查＋本地系统通知。发布者更新清单后，常驻客户端在下一次检查时获知更新；应用完全退出时不能接收。这不是实时服务端推送，但更适合目前产品的更新提醒需求。

## 三种路径

| 路径 | 常驻时延 | 应用退出后 | 服务成本与限制 |
| --- | --- | --- | --- |
| HTTPS 清单轮询 | 每 24 小时；每次启动延迟后检查，失败短间隔退避 | 下次启动检查 | 静态托管即可，推荐第一阶段 |
| SSE/WebSocket | 可接近实时，断线后需补查清单 | 不能接收 | 自建连接服务、心跳、代理/休眠重连及广播；只适合确有实时需求 |
| APNs＋WNS | 通常较及时，但不是可靠送达保证 | 依赖系统与应用身份/签名支持 | 两套推送体系、设备注册、凭据与失效处理；适合明确要求退出后提醒的阶段 |

## 共享发布契约

托管一个有 schemaVersion 的 HTTPS updates.json，按 stable/beta、macos-arm64/windows-x64 分条目。每项至少包含版本、releaseTag、publishedAt、minOS、releaseNotesURL、downloadURL、包摘要和可用状态。保留显式平台键；JSON 不携带脚本或任意可执行命令。客户端只打开允许的 HTTPS 发布地址，默认用户手动下载安装。

现阶段可用 GitHub 公共发布资产作为下载地址。清单可由静态站点托管，位置在实施时再确定。不要在客户端嵌入 GitHub Token；匿名 REST API 按来源 IP 通常每小时 60 次，在共享出口场景容易受限。直接扫描 GitHub releases 是低成本备选，但要遍历公开稳定版本、按完整平台资产筛选，再做语义版本比较，不能直接使用 releases/latest。

发布流程顺序：准确 tag 构建 → 当前平台原生验证及来源验证 → 上传不可覆盖资产 → 公开且确认下载可用 → 更新该平台清单指针。平台分批发布时仅推进已成功的平台；另一平台保留原有效版本。并发发布需串行或原子合并，不能后写覆盖另一平台条目。清单发布失败可重试，不撤销已有正式包；保留上次有效清单。不要用不可变 release 中的清单作为永远不变的发现 URL，应提供稳定入口。

第一阶段只提醒、打开发布页；下载摘要用于后续可信下载设计，单独 SHA256 不能防止清单与包同时被替换。未来自动安装需要签名清单、固定验证公钥/轮换方案、平台代码签名及事务回退，不包含在通知功能内。

## 客户端逻辑

每次启动延迟约30秒检查，不受上次成功时间抑制；成功后常驻每24小时检查，失败继续短间隔指数退避；手动检查有独立短节流。HTTPS 超时、有界响应、单请求并发、ETag/缓存、断网指数退避；失败不影响额度查询，不把网络故障说成已是最新版。

依据平台/架构/渠道/minOS/公开可用性筛选；语义版本比较，例如 0.10.0 大于 0.9.0，stable 不接受 prerelease；旧版不提示，开发候选依来源标识明确显示，不能与同版本正式包混淆。相同版本候选到正式版可显示状态转换，不默认当作强制升级。

本地保存 lastSuccessfulCheck、lastNotifiedVersion、skippedVersion、snoozeUntil 和通知偏好。同一版本不重复打扰，跳过仅跳过该版本；发现更新仍在设置中可见。通知发送失败/权限关闭时保留应用内入口，不能因为已发现就误记为已成功提醒。支持三语言，提供自动检查、系统提醒、立即检查、稍后提醒与跳过版本。

## 平台适配

macOS：使用 URLSession 检查，UNUserNotificationCenter 发本地通知，在用户启用系统提醒时解释用途并请求权限；通知点击打开更新详情/发布页，主线程处理 UI。拒绝权限时保留菜单/设置提示。当前本地签名候选与正式签名身份变化后的权限行为，需要 macOS 真机验证，不能以单元测试替代。

Windows：HttpClient 检查。现有 NotifyIcon.ShowBalloonTip 可作低依赖第一版，点击跳转及去重可复用托盘对象；系统实际呈现和通知中心行为需 Windows 11 验收。更完整的通知操作按钮/激活可使用 Windows App SDK AppNotificationManager，支持 WPF 和 unpackaged 应用；需要评估 SDK 运行时、自包含包体、注册与卸载清理，不能假设加入 NuGet 即完成。

真正远程推送：macOS 需 APNs 注册、推送 App ID、macOS APS entitlement 与有效签名/配置，服务端持有发送凭据并管理设备 token；当前普通本地签名不等同已具备 APNs 身份。Windows WNS 需 Windows App SDK、Azure/Entra 应用身份和通道注册；官方文档指出无 package identity 的 unpackaged 模式功能受限，后台投递/COM 激活需要 package identity。退出后通知的需求必须先验证打包/身份模型，不能承诺当前 ZIP 应用直接支持完整后台推送。推送只作为版本变更提示，客户端仍获取并验证清单，漏推后靠轮询补偿。

## 验证和阶段

阶段一：平台清单及发布接入、两端检查器、设置/菜单提示、系统提醒和手动发布页入口。工程估算约 3–5 个有效开发日，不含证书/平台设备等待；这是规划估算。

阶段二：仅在秒级/退出后提醒明确必要时评估实时服务或 APNs/WNS。自动下载安装单独立项。

验收：跨平台发布错位、缺资产、draft/prerelease、同版本候选、版本比较、minOS、畸形/超大清单、断网/超时/限流、缓存失效、同时唤醒/网络恢复、重启去重、跳过/稍后、通知权限关闭、点击激活、安装升级保留偏好，以及实际 macOS 和 Windows 11 的通知行为。服务故障不应影响额度采集。当前仅完成源码/公开资产/官方文档分析，未实现、未运行通知实机测试。

## 官方资料

- Apple 权限：https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
- Apple APNs 注册：https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns
- macOS APS entitlement：https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.aps-environment
- Windows .NET 本地通知：https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-dotnet
- Windows 推送及打包限制：https://learn.microsoft.com/en-us/windows/apps/develop/notifications/push-notifications/push-quickstart
- NotifyIcon：https://learn.microsoft.com/en-us/dotnet/desktop/winforms/controls/notifyicon-component-overview-windows-forms
- GitHub REST 限流：https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
