# Character Notification Bubbles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 按已选C角色对话方案，用统一渠道路由呈现两端现有恢复、Bank、更新和示例提醒。

**Architecture:** 事件引擎保持原观测与收据语义；Core新增纯展示状态机和锚点布局。原生路由持有状态机，平台窗口只绘制并报告展示/交互，Coordinator仅提供环境与导航。macOS更新投递纳入同一路由，避免独立授权/去重路径。

**Tech Stack:** Swift 6、AppKit、UserNotifications；.NET 10、WPF、NotifyIcon；已有三语言文案与原生测试设施，无新增依赖。

**Spec:** [C角色对话提醒设计](../specs/2026-10-22-character-notification-bubbles-design.md)

## Global Constraints

- macOS 14+ Apple Silicon；Windows 11 x64，保留官方内嵌运行时0.144.1和隔离账户。
- 默认悬浮气泡；保留既有开关false、notified/skipped/snooze、Bank收据；不因切换渠道补发旧事件。
- 2026-10-22用户追加：所有气泡取消固定6/10秒超时，额度不变持续显示，完整新鲜查询确认原始使用率改变后收起；非活跃未读最多32条/24小时；恢复自动展示有效期5分钟，Bank最新完整数据<=120秒。
- 角色40×48、间距8；气泡常规宽320/最小260、边距14、圆角16；屏幕工作区边距8，不改变现有浮窗尺寸。
- 约150ms淡入，收起/取消即时隐藏；减少动画时直接显示；不抢焦点、无声音、无循环角色动画。
- 浮窗隐藏、锁屏、休眠、拖动、右键、详情展开时不冒泡；不自动转系统通知；有效事件进入仅本次运行的未读集合。
- 三语言、浅深色、键盘/读屏入口；不新增预警/预测、自动兑换、自动安装；不发布、不改版本、不覆盖本地已安装应用。

## Review Focus

- 气泡可见后晚到旧账户回调：任何动作必须再次核验epoch，取消不能导航新账户（任务2/3/4）。
- 同优先级多个事件及两渠道异步完成：FIFO稳定，展示回执最多一次，旧回调不能消费新消息（任务1/2/4）。
- 隐藏或长时间锁屏后：不补播过时恢复，不用旧Bank数据宣称仍临期（任务1/5）。
- 详情悬停与气泡鼠标区域相邻：穿过角色/间隙不误开详情，右键只显示菜单（任务3/4）。
- 长英文、两阶段Bank、多屏负坐标、缩放：完整信息可在详情/列表访问，窗口不越界或缩小字号（任务1/3/4/6）。

---

### Task 1: 展示状态机、偏好与共享契约

**Files:** Create `contracts/notifications/presentation-sequences.json`, `native/Sources/QuotaCore/NotificationPresentation.swift`, `native/Sources/QuotaCore/NotificationBubbleLayout.swift`, `native/Tests/QuotaCoreTests/NotificationPresentationTests.swift`, `windows/QuotaBar.Core/NotificationPresentation.cs`, `windows/QuotaBar.Core/NotificationBubbleLayout.cs`, `windows/QuotaBar.Core.Tests/NotificationPresentationTests.cs`. Modify `windows/QuotaBar.Core/Preferences.cs`, `windows/QuotaBar.Core.Tests/Program.cs`。

**Interfaces:** Swift/C#对应语义：`NotificationDeliveryMode`四值bubble/system/both/off；`NotificationPresentationPreferences(mode, pausedUntil)`；`NotificationPresentationState.enqueue(message, now)`, `next(environment, now)`, `shown(id, now)`, `dismiss(id, read, now)`, `setInteracting(active, now)`, `cancel(epoch)`, `unread(now)`, `stop()`；布局`NotificationBubbleLayout.place(anchor, workArea, size) -> rect?`。状态转换返回显式效果，不直接操作UI/时钟/持久化。

- [x] 写失败用例：缺少/非法渠道默认bubble、暂停时间往返、旧false保留；同ID去重、恢复优先于Bank/更新、相同类型FIFO、上限32淘汰最低优先级最旧项。
- [x] 写时间序列断言：`shown`后6/10秒收起；悬停3秒后恢复剩余时长；隐藏队列不生成shown；恢复301秒不自动显示；24小时清理；旧epoch移除；stop后无效果。共享JSON提供now、消息、环境、操作和期望可见/未读ID。
- [x] 写布局断言：上方优先/翻下、8单位边界、负坐标、屏幕不足返回nil；两端按同一规范归一坐标，macOS原生适配处理Y轴方向。
- [x] 运行 `xcrun swift test --package-path native --filter NotificationPresentationTests` 和 `dotnet run --project windows/QuotaBar.Core.Tests -c Release`，确认因类型缺失失败。
- [x] 最小实现上述接口，Windows将新测试注册至Program；Swift偏好序列化作为独立值，不写现有事件收据。
- [x] 重跑两条命令并确认新用例与共享序列通过；提交 `feat: add notification presentation state and layout`。

### Task 2: macOS统一路由与投递回执

**Files:** Modify `native/Sources/CodexQuota/AppNotificationRouter.swift`, `native/Sources/CodexQuota/QuotaExperienceController.swift`, `native/Sources/CodexQuota/QuotaUpdateController.swift`；Create `native/Tests/CodexQuotaTests/NotificationRoutingTests.swift`。

**Interfaces:** `enqueue(message, valid, failed, shown)`；目的地`NotificationDestination.details/bank/update(version)`；可注入系统投递和气泡呈现闭包；`configure(preferences)`, `updateEnvironment(environment)`, `cancelAuthenticationEpoch(epoch)`。消息ID及回执均绑定原始事件，不靠标题解析。

- [x] 写失败测试：bubble无授权请求；系统拒绝不阻挡both的气泡；两渠道完成仅一次shown；入队未展示不记录更新notified；skip/snooze仍抑制；登出后动作失效。
- [x] 聚焦运行 `xcrun swift test --package-path native --filter NotificationRoutingTests` 确认失败。
- [x] 接入任务1纯状态机；保留唯一UNUserNotificationCenterDelegate；将更新通知改走enqueue，shown回调记录原UpdateReminderPolicy；Bank展示前使用原valid闭包复核。
- [x] 恢复/Bank权限请求仅发生在渠道含system且用户主动开启时；示例不碰真实收据/基线；无窗口宿主时进入未读而非静默标记shown。
- [x] 聚焦测试加原`ExperienceNotificationTests`、`QuotaExperienceTests`、`UpdateFeedTests`全部通过；提交 `feat: route macOS reminders through delivery channels`。

### Task 3: macOS角色气泡与浮窗生命周期

**Files:** Create `native/Sources/CodexQuota/CharacterNotificationBubble.swift`, `native/Sources/CodexQuota/NotificationUnreadPanel.swift`, `native/Tests/CodexQuotaTests/CharacterNotificationBubbleTests.swift`；Modify `native/Sources/CodexQuota/FloatingQuotaButton.swift`, `native/Sources/CodexQuota/StandaloneCoordinator.swift`, `native/Sources/CodexQuota/QuotaMoodView.swift`。

**Interfaces:** `CharacterNotificationBubble.show(message, destination, frame, theme, language)`, `dismiss()`, `onAction`, `onAcknowledge`, `onInteractionChanged`；`FloatingQuotaButton.onDragStarted`, `hasUnread`, `onUnreadRequested`；窗口宿主报告实际可见后调用router.shown，列表接收未读模型而不是原始协议。

- [x] 写失败测试：面板不激活、角色非交互、查看/知道了独立、长文本无溢出、深浅主题、close/drag/outside关闭、减少动画不建立重复计时器、未读列表语义。
- [x] 运行 `xcrun swift test --package-path native --filter CharacterNotificationBubbleTests` 确认失败。
- [x] 实现原生角色、左尾气泡、标签、两动作；复用角色绘制，Bank加钟/更新加箭头；图标旁未读点不侵入数字与关闭槽位。严禁运行时加载概念图。
- [x] 将详情/右键/拖动/浮窗隐藏、锁屏/休眠、屏幕变化转环境状态；关闭应用清理窗口/计时器/观察者；菜单提供键盘可达未读入口，列表过时内容降级文案。
- [x] 渲染三语言×浅深色×恢复/Bank/更新/示例截图并检查；聚焦测试与`FloatingQuotaButtonTests`、`SettingsPolishTests`通过；提交 `feat: present character reminder bubbles on macOS`。

### Task 4: Windows统一路由、WPF气泡及生命周期

**Files:** Create `windows/QuotaBar.Windows/CharacterNotificationBubble.cs`, `windows/QuotaBar.Windows/NotificationUnreadWindow.cs`；Modify `windows/QuotaBar.Windows/AppNotificationRouter.cs`, `windows/QuotaBar.Windows/Coordinator.cs`, `windows/QuotaBar.Windows/FloatingWindow.cs`, `windows/QuotaBar.Windows/QuotaMoodView.cs`, `windows/QuotaBar.Windows/UpdateController.cs`, `windows/QuotaBar.Windows/QuotaExperienceController.cs`, `windows/QuotaBar.Windows.Tests/Program.cs`。

**Interfaces:** 与任务2/3对齐；路由接收`Enqueue(message)`，展示回执使用ID；WPF宿主`ShowMessage(message,frame,theme,copy)`和单次动作回调；通知不依赖BalloonTip事件驱动气泡通道。

- [x] 写失败测试：bubble不调用NotifyIcon、both单次shown、旧BalloonTipClosed/Clicked不影响下一气泡、隐藏更新不记已展示、登出取消动作；Core共享序列沿用任务1。
- [x] 写原生UI断言：ShowActivated=false/无任务栏、控件可访问名称、角色不拦截点击、DPI100/150/200布局、长英文/两阶段Bank及右键互斥。
- [ ] 在Mac运行 `dotnet build windows/QuotaBar.Windows.Tests -c Release`确认新接口缺失导致失败；Windows运行原生测试确认行为失败，不能以跨编译替代。
- [x] 实现WPF角色对话窗与未读窗，复用被动窗口机制；接Core队列并隔离系统/气泡生命周期；处理锁屏、休眠、位置变化、详情和context menu，停止清理。
- [x] `dotnet run --project windows/QuotaBar.Core.Tests -c Release`与全部Windows工程构建通过；Windows原生测试/截图独立记录；提交 `feat: present character reminder bubbles on Windows`。

### Task 5: 设置、迁移与三语言入口

**Files:** Modify `native/Sources/CodexQuota/QuotaExperienceController.swift`, `native/Sources/CodexQuota/QuotaUpdateController.swift`, `native/Sources/CodexQuota/StandaloneCoordinator.swift`, `native/Tests/CodexQuotaTests/SettingsPolishTests.swift`, `windows/QuotaBar.Windows/SettingsWindow.cs`, `windows/QuotaBar.Core/Preferences.cs`, `windows/QuotaBar.Windows.Tests/Program.cs`。

**Interfaces:** 统一偏好使用任务1类型；macOS键`notifications.presentation`存版本化JSON值，WindowsPreferences新增对应属性；暂停截止时间UTC存储，界面按当前语言呈现。旧体验/更新偏好不重置。

- [x] 写失败测试：四渠道选择、保存重启、缺省迁移、各开关独立、暂停1小时/恢复、系统权限拒绝提示只影响system、示例不改真实状态。
- [x] 设置加入渠道、暂停/恢复、预览气泡、未读入口，去除气泡模式下的系统权限误导文案；三语言同步。隐藏浮窗预览不唤出，提供显式开启按钮。
- [x] 测试锁屏/隐藏后未读点及列表，超时不补播，列表Bank过期措辞更新；两者模式一次事件最多一气泡加一系统通知。
- [x] 运行全部Swift及Windows Core测试、Windows UI构建；截图检查设置无重复控件/截断；提交 `feat: add reminder channel and unread controls`。

### Task 6: 完整回归、候选与交付证据

**Files:** Modify `README.md`, `README.zh-CN.md`, `docs/PRIVACY.md`, `docs/TROUBLESHOOTING.md`, `docs/PROJECT_PROGRESS-standalone-app.md`；Create `docs/validation/2026-10-22-character-notification-bubbles.md`；按需修改`.github/workflows/`中现有原生CI，加入新测试而不绕过门禁。

- [x] 对照规格第7节逐条记录实现/测试/未执行，重看所有路由回执、epoch取消、旧policy迁移和原生事件边界；不得仅以构建成功证明UI可用。
- [x] 执行 `PATH="$HOME/.local/share/quotabar-dotnet:$PATH" ./governance check all`，期望退出0；保留日志。
- [x] 执行`CUS_RUNTIME_BINARY=<已验证0.144.1运行时路径> bash scripts/build-macos-standalone.sh`，构建候选并通过原生启动退出、签名检查；使用独立测试配置打开，不覆盖已安装应用/账户。
- [x] Windows现有原生CI运行新增交互与渲染测试；若需要推送运行CI，先本地完整治理，再推送功能分支/草稿PR，不合并/发布。Windows设备不可用时记录真实缺口，候选保持待设备验收。
- [ ] macOS实机检查三语言、深浅色、拖动/悬停/右键/外部点击、真实窗口焦点、锁屏/休眠、显示器边界；能执行的设备场景记录截图，未执行矩阵明确列出。
- [x] 更新README/隐私/排错：提醒渠道默认、未读仅本次运行、气泡不自动继承系统免打扰、如何暂停、测试通知区别；维护路线图和看板并validate。
- [x] 提交 `docs: document character bubble reminder validation`；交付候选路径与当前验证限制，不宣布公开发布。

## 执行与审阅

计划自检覆盖：规格1–3由任务3/4/5负责；规格4由任务1–5负责；规格5由任务2/4/5负责；规格6由任务1–5负责；规格7由任务6及各任务测试负责。已补充回执竞态、鼠标区域互斥、未读时效、窄屏和长文本输入。

建议本会话原生执行（Native）：任务接口依赖紧密，先Core再两端适配；全分支完成后独立审查。用户已确认计划及当前会话原生执行，产品实现与验证记录如下。

## 执行结果与偏差

- 任务1–5已实现并提交；失败测试与修复包括渠道迁移、both权限拒绝、稍后重新布防、双渠道动作消费、旧投递回调隔离、四行正文与窄宽按钮边界。
- Windows缺失类型的失败跨编译已观察；本机没有Windows，未先在原生Windows上运行行为失败版本。后续原生CI运行全部行为与UI测试，不将跨编译当作原生证据。
- 任务6完整治理通过；macOS候选为干净源码构建，原生CI/Windows候选和具体运行编号见[验收记录](../../validation/2026-10-22-character-notification-bubbles.md)。
- macOS真实非激活面板和隔离候选启动退出已测；三语言/两主题用原生内容渲染验证。未逐项完成人工锁屏休眠、多屏/Space、读屏器、长期占用；Windows人工设备矩阵同样待验收。上述两项未完成的步骤保留未勾选。
- 为避免取消后残留，保留150ms淡入、收起时即时隐藏；不新增退出动效计时器。
- 最终源码独立审查发现的重要问题均已修复；没有执行安装覆盖、main合并或公开发布。

## 用户追加：持续显示与本机安装

用户选择“所有气泡，包括更新和示例”，并明确授权修改后安装本机。使用当前功能分支追加Core配额比较基线和原生完整查询接入；同额度/时间戳/局部/旧响应不收起，原始使用率变动收起，已知可选周期缺失不当零。此追加覆盖原6/10秒与悬停剩余倒计时用例，主动/安全生命周期关闭继续保留。Core/路由失败回归→最小实现→完整治理→独立审查→候选签名隔离启动→事务安装并核对运行状态，Windows原生CI独立记录。不包含合并发布。
