# 应用内下载安装更新

本功能处于开发候选阶段，未公开发布。已安装的v1.3.0不包含更新助手，须先手动安装首个含此功能的正式版本；之后可在“设置 → 关于应用”点击“立即更新”。

## 使用与失败处理

发现更新仍沿用现有清单、启动约30秒首次检查、成功后每24小时检查、失败退避、稍后提醒与跳过版本规则。只有明确点击“立即更新”才下载；通知栏和未读列表点击打开关于应用。气泡中明确标为“立即更新”的按钮可直接开始。

下载与校验期间可取消，额度查询继续。界面显示下载量、校验和准备状态；助手确认就绪后，应用正常退出，替换安装并重启。系统签名/钥匙串授权提示仍由操作系统处理。启动回执先于钥匙串读取，不会因等待授权而回退。基本启动检查为15秒内回执和之后2秒进程存活，不代表真实账户、网络或未来所有功能已验收。

仅支持标准每用户目录：macOS `~/Applications/QuotaBar.app`，Windows `%LOCALAPPDATA%/Programs/QuotaBar`。从DMG、下载目录或自定义目录运行时，先手动安装到标准位置；不会替换任意路径或请求管理员权限。

网络、API限流、缺失资产、摘要或来源不符、磁盘不足、助手未就绪：保留当前运行版本，显示重试与发布页手动安装入口。助手就绪前取消只清理本次暂存目录。替换/启动失败恢复旧目录与注册信息并重新启动旧版；旧备份保留。进程在关键位置崩溃时保留事务日志。macOS再次从标准位置启动时会交给日志绑定的旧助手恢复；若应用目录缺失，可运行该任务目录中的 `QuotaBarUpdater --recover <任务目录> 0`。Windows可使用保留的当前setup执行 `recover` 或重新安装。不要手工删除唯一旧备份。

## 信任、隐私与包契约

不增加服务器、付费API、用户GitHub token或后台自动安装。发现清单只提供版本提示；点击后固定向 `api.github.com/repos/JaceHwang/QuotaBar` 查询正式release与精确tag，拒绝草稿、预发布、降级、非固定来源或不安全重定向。下载只使用GitHub及其明确允许的HTTPS资产域名，无Cookie、账户令牌或认证头。

校验官方资产size/SHA256、tag commit、版本、平台、来源证明、包身份及完整文件摘要。GitHub仓库的HTTPS元数据是信任来源；SHA256不是独立发行者签名。当前签名/公证能力不因此改变，不绕过Gatekeeper、Defender或系统提示。官方API或必要digest不可用时失败关闭，用户仍可手动安装。

macOS新包包含原生 `Contents/Helpers/QuotaBarUpdater`，证明包含 `updateProtocol: 1` 与 `updaterSignedSha256`。先复制当前安装的助手再运行。Windows先复制当前 `setup` 目录；助手对照已校验原始ZIP重新解压并核对暂存清单，复用事务安装器。旧版不满足助手协议时不能作为自动更新目标。

私有更新目录保存本次安装包、来源证明、schema1任务和ready/health/结果回执，不保存Key、邮箱、凭据或原始账户协议。路径：macOS `~/Library/Caches/com.jace.codex-quota/Updates`，Windows `%LOCALAPPDATA%/QuotaBar/Updates`。任务nonce与父进程身份用于防误用及重放；任务10分钟过期。失败只删除本操作的暂存，成功/交接后的记录保留用于排查，不主动删除正在运行的助手。

## 开发验证

- `swift test --package-path native`：共享发布契约、下载/取消、实际只读DMG准备、事务回退、状态与三语言UI。
- `dotnet run --project windows/QuotaBar.Core.Tests`：同批契约、HTTP边界、恶意ZIP、伪造暂存清单、事务与取消状态。
- `python3 scripts/test-macos-in-app-update.py`：生产原生助手真实进程，隔离HOME与签名夹具；不读取真实钥匙串。
- Windows原生CI构建候选后运行 `python scripts/test-windows-in-app-update.py <QuotaBar目录>`，要求干净测试账户，拒绝覆盖已有安装或真实凭据。验证真实父进程退出、就绪、安装、基本启动、失败回退、过期/损坏/重放及数据标记保留。
- 两端原生证据分别记录，交叉构建不代替Windows实机。候选不能代替自然真实更新或用户设备验收。公开发布仍须明确授权与Release Please准确tag流程。
