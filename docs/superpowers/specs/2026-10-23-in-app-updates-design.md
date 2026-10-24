# QuotaBar 应用内一键更新设计

日期：2026-10-23。用户选择“点击后下载并安装”，已授权开发；视觉确认沿用现有蓝色按钮与卡片，跳过效果图。此文件细化已选流程，随实施计划一起审阅后执行。本轮为macOS/Windows开发和候选验证，不自动延续上一轮公开发布授权。

## 目标与用户流程

在更新气泡或“关于应用”点击“立即更新”，完成解析官方版本→下载（进度/取消）→校验→准备安装→退出应用→独立助手替换→重启。无需到网页手动下载，不后台预下载，不静默安装。首次安装包含更新助手的版本仍需现有安装方式；当前v1.3.0不会凭空获得该能力。

关于页保留“查看更新内容”“稍后提醒”“跳过此版本”及原自动检查/提醒设置。系统通知点击只打开应用更新区域，气泡明确标为“立即更新”的主操作及关于页按钮才直接启动下载。手机Bark提醒不获得远程安装能力。

## 视觉简报

直接沿用已验收设置C风格；蓝色#0065D8、30pt按钮、13pt半粗体、7pt圆角和12pt水平留边，宽度随文案增长，最小100pt。版本卡中放单行阶段、进度条与取消按钮，失败显示短分类及“重试”“查看发布页”。简中/繁中/英文、浅/深色、840×560滚动均覆盖。保持键盘与读屏进度反馈；不用全屏动画，不抢焦点。安装交接后不再允许取消，显示“正在安装，即将重启”。用户指定现有风格直接实施，为本次不生图的明确原因。

## 状态与生命周期

`idle → resolving → downloading → verifying → preparing → handingOff → installing → succeeded | rolledBack | failed`；取消仅作用于resolving/downloading/verifying/preparing。各阶段采用一个操作ID和版本快照，重复点击不并发。取消、退出和晚到响应不能启动安装。下载期间正常额度查询/提醒继续；交接才正常退出并停止自有运行时。更新检查不得改写正在进行的目标版本。

不自动重试下载或安装。下载失败/取消清理本次临时文件，保留运行中的旧应用；重试由用户发起。进行中的安装使用跨进程锁和原子日志/结果回执，重启后可恢复未完成事务，不能凭缓存自动发起一次新的安装。

## 来源和完整性契约

继续用现有Pages更新清单发现版本，不改旧feed字段与兼容性。用户点击后只访问固定仓库`JaceHwang/QuotaBar`的GitHub API：按确切`v<version>`取得正式、非草稿、非预发布release，再解析对应git tag（注解tag最多解析两层）至40位commit。版本必须比当前版本高，OS仍符合清单与包内最低系统要求。

精确选择当前发布资产名：Mac `codex-quota-v<version>-macos-arm64.dmg`与`CODEX-QUOTA-PROVENANCE.json`；Windows `QuotaBar-<version>-windows-x64.zip`与`QUOTABAR-WINDOWS-PROVENANCE.json`。要求state=uploaded、唯一名称、0<size<=512MiB、有效`sha256:<64位小写hex>`、固定仓库/确切tag的下载URL。元数据最多2MiB，来源文件最多1MiB；无digest、缺少任一资产或API限流时停止并保留手动发布页入口，绝不跳过校验。

API请求仅固定`https://api.github.com`路径且不自动重定向；下载初始URL仅允许精确官方发布路径，重定向仅HTTPS、无userinfo/自定义端口，显式允许`github.com`、`release-assets.githubusercontent.com`、`objects.githubusercontent.com`，最多10次。不可访问任意feed提供地址、HTTP或本机地址。禁止使用用户GitHub token、Cookie、Codex凭据或Bark Key。元数据与下载只在显式更新时请求，无新服务器/付费API。

流式下载，进度以可信asset size为分母，实际字节不得超限且最终size、SHA256与API一致。来源文件本身也按API摘要校验；包内product/platform/version/releaseTag/sourceCommit与目标及git tag匹配。Windows沿用完整package.json逐文件校验，Mac核对bundle ID、Info版本/最低系统、codesign结构及来源记录中的可执行文件/运行时摘要。不是把SHA256当作独立发布者签名：信任根是HTTPS官方GitHub仓库，不能抵御仓库/发布凭据被攻陷；本轮不声称新增Apple公证或Windows Authenticode签名，不关闭系统安全检查。

依据：[GitHub release assets](https://docs.github.com/en/rest/releases/assets)与[release API](https://docs.github.com/en/rest/releases/releases)。公开资产可免认证取元数据，返回size/digest及browser_download_url；二进制下载可能302，需受控处理。

## 暂存与包校验

每次更新使用私有UUID目录及锁，Mac目录0700；固定在现有应用数据根的update-cache下，不写登录、Key或偏好目录。JSON任务和回执不含凭据，不记日志中的临时下载签名query。只清理非活动、可确认属于本应用的缓存，保留最新结果与旧安装备份。

Windows先检查ZIP中央目录再解压：禁止绝对/父级/反斜线路径、重复/大小写冲突、链接/reparse项及解压越界，最多20000项、总展开<=2GiB；仅允许完整QuotaBar目录。Mac受控只读挂载DMG到本次目录，复制唯一QuotaBar.app后卸载，拒绝链接及越界内容。检查磁盘空间能容纳下载/暂存及事务复制（至少2倍包展开量+64MiB安全余量，按阶段扣除已占空间），空间不足在退出前失败。

## 安装助手与回退

仅支持现有标准每用户路径：Mac `~/Applications/QuotaBar.app`，Windows `%LOCALAPPDATA%/Programs/QuotaBar`。当前进程与安装位置不符（如DMG/下载目录）时不替换其他路径，提示先正常安装并提供发布页。助手不请求管理员权限、不改系统目录，不接受网络指定目标路径。

Mac新增原生Swift可执行助手随app签名打包，不依赖Python；复制当前受信任助手到暂存区后运行。Windows复制当前安装的setup目录到暂存区，新增受控update命令并复用TransactionInstaller；不先执行下载包内的setup。安装前助手重新验证暂存包、预期版本、目标路径、父进程身份与摘要，拿锁后发送ready，应用收到ready才正常退出。助手ready握手最多10秒；任务在生成后10分钟过期；父进程在20秒内未退出则放弃，不覆盖运行中应用。

安装保持登录、Bark Key、偏好、浮窗位置和开机启动状态；原安装目录同卷备份并原子替换。安装/注册失败恢复旧应用及注册状态并重开。启动新版本后使用随机nonce的原子health回执（15秒内）和随后2秒存活检查确认基本启动，失败则回退并重开旧版；记录分类结果供下次显示。不把网络额度查询成功作为启动条件；health在系统钥匙串交互前确认应用基本启动，系统授权等待不导致误回退。此健康检查不承诺对后续任意运行期缺陷自动降级。

任务文件只含本地版本、来源摘要、受控路径、父进程与nonce；助手拒绝过期/重复/不属于当前私有目录的任务。会话ID、原子状态和跨进程锁阻止双击/多实例造成重复替换。退出/下载取消不会改登录状态或发送测试Bark。

## 验收与边界

两端使用同一批脱敏release/tag/asset fixture，覆盖缺字段/假URL/重定向/digest缺失或错误/过大/降级/预发布/资产未齐/错误平台。故障覆盖网络中断、取消后晚到、双击、校验期间退出、磁盘不足、ZIP越界/重复/链接、包摘要不符、助手未就绪/父进程未退出、替换失败、启动即退及崩溃恢复。

原生端到端验证实际助手进程与已打包应用，使用隔离数据/可控fixture，不操作用户真实凭据或冒充官方新release；Windows必须在Windows runner执行安装/回退/重启，不能以交叉构建替代。Mac验证全新安装及已登录/Key已配置时的系统授权边界，真实密码由用户输入。三语言/两主题/窄窗截图、现有更新提醒/跳过/稍后、退出运行时和稳定feed兼容均回归。阶段证据区分源码、本地、原生CI、用户设备和公开发布。
