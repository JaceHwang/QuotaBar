# macOS standalone implementation plan

## Scope and authorization

用户要求持续推进至 macOS 开发完成、打包安装测试通过；采用原生实现，沿用当前详情设计，明确跳过效果图。Windows 不属于本次完成门槛，公开发布不在授权范围。

## Implementation sequence

1. 独立采集：使用本机官方 CLI 固定版本验证握手、账号和额度；记录失效登录，不复制凭据。当前 CLI 0.144.1 握手成功，隔离目录登录已过期，真实额度验收等待官方重新登录。
2. 数据状态：在 SidebarCore 添加可测试的独立运行状态、刷新策略及协议错误/登录事件；回归保证主额度失败可见，可选接口局部降级。
3. 原生应用：新增 StandaloneCoordinator 和菜单栏入口，通过内嵌运行时启动；不构造 RuntimeCoordinator/AX/UIA。复用 QuotaDetailPanel。设置提供主题、语言、账号、刷新、登录启动与退出。
4. 账户生命周期：官方 account/login/start 浏览器流程、cancel/logout，维护独立 CODEX_HOME；支持现有隔离目录的受控复用，不读取凭据文本。超时/离线/恢复状态清楚。
5. 打包：新增专用 standalone 构建脚本，输出独立 bundle 与 DMG，携带官方运行时、许可、资源和来源摘要；不改版本，不覆盖已发布资产。
6. 安装验证：安装到用户 Applications，验证签名、资源、菜单栏、真实数据/登录、启动关闭与子进程清理；验证迁移不会被旧 hook 重新启动。每次验收同步详细进度和看板。

## Evidence and gates

新增数据行为先测试后实现；完成后运行完整 Swift 套件、治理检查、打包校验及真实安装运行验证。演示快照只用于界面测试，不能作为真实账号额度证据。不能为了测试退出当前执行任务的 Codex 桌面进程；通过不包含宿主发现路径的独立进程验证，再安排可观察的宿主缺席测试。

## File boundaries

- SidebarCore：独立状态与 app-server 账户/错误事件。
- CodexUsageSidebar/StandaloneCoordinator.swift：菜单栏及独立生命周期。
- CodexUsageSidebar/StandaloneSettings.swift：原生设置和官方登录入口。
- main.swift：独立 bundle 入口分支，保留历史伴生入口。
- scripts/build-macos-standalone.sh：构建、运行时与资源打包。
- docs/validation/macos-standalone.md：真实验收证据。

## Risks

登录过期必须由官方流程恢复；公证依赖可用身份；运行时协议能力按固定版本测试；旧插件启动机制与独立安装不能并行重复采集。
