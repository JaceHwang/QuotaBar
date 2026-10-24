# Notification Category Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为macOS/Windows交付固定提醒分类与三渠道独立选择，并增加偏低/耗尽事件。

**Architecture:** 保留现有提醒检测与原生发送适配器，新增纯分类策略、单次迁移与渠道级投递状态。两端通过共享fixture保持一致，先迁移现有事件，再新增预警。

**Tech Stack:** Swift/QuotaCore/AppKit、C#/.NET/WPF、JSON fixtures、现有治理与原生CI。

**Spec:** `docs/superpowers/specs/2026-10-24-notification-category-matrix-design.md`（执行前须审阅批准；本计划为同步待审草案）。

## Global Constraints

- 两阶段全部完成才算本需求完成；各阶段独立验证。
- 新增偏低阈值默认20，可选10/20/30；新增偏低、耗尽默认所有渠道关闭。
- 新安装恢复、Bank气泡默认开，更新所有渠道默认关；系统/手机默认关。
- 升级保持已有实际通知范围；动画不再隐式开启提醒；重新开启不补发。
- 凭据只使用现有安全存储；手机服务接受不等于iPhone展示。
- 不修改产品版本、不自动安装或发布；实施前governance doctor并使用codex分支。

## Review Focus

- 旧庆祝开启而恢复关闭：迁移保留原恢复通知，后续改动画不改通知（任务2）。
- 关闭后立即重开、发送晚到：不能跨配置复活任务或写错误收据（任务3）。
- 阈值处震荡和重启：同一周期偏低最多一次（任务5）。
- Bank首次观察已不足24小时：不补发72小时（任务4）。
- Keychain不可用/阻塞：启动与桌面渠道不被手机拖住（任务3、6）。

## 文件职责

新增 `native/Sources/QuotaCore/NotificationPolicy.swift` 与 `windows/QuotaBar.Core/NotificationPolicy.cs`：类别、渠道、偏好、策略决策、迁移。
新增 `native/Sources/QuotaCore/QuotaWarningEngine.swift` 与 `windows/QuotaBar.Core/QuotaWarningEngine.cs`：跨线及持久化状态。
新增 `contracts/notifications/matrix-cases.json`、`migration-cases.json`、`warning-cases.json`：跨平台协议样例。
修改两端 `ExperienceNotification`：增加类别/事件元数据，不用角色或文案分类。
修改两端 `QuotaExperience`、`QuotaExperienceController`、`AppNotificationRouter`、`BarkNotificationController`、`QuotaUpdateController.swift` / `UpdateController.cs`：检测、路由、收据和更新接线。
修改 macOS `NotificationSettingsView.swift`、`BarkSettingsView.swift` 与Windows `SettingsWindow.cs` 及其现有提醒/手机区域：设置呈现。执行时先定位Windows实际组件，避免在大窗口中重复实现。
测试放在现有 `native/Tests/QuotaCoreTests`、`native/Tests/CodexQuotaTests`、`windows/QuotaBar.Core.Tests`、`windows/QuotaBar.Windows.Tests`。

### Task 1: 分类契约与纯策略

**Files:** 新增 NotificationPolicy 双端文件、matrix-cases.json；修改双端 ExperienceNotification；新增两端 NotificationPolicyTests（.NET注册到既有Program测试入口）。

**Interfaces:** Swift `NotificationCategory: String, Codable`、`NotificationChannel: String, Codable`、`NotificationPolicyPreferences`、`NotificationPolicy.decision(category:channel:preferences:now:) -> NotificationDecision`；C#提供同名类型和PascalCase静态方法，JSON标识统一camelCase。Decision含allowed/ruleOff/channelOff/paused。

- [ ] 编写fixture：6×3单元格开关、总开关、暂停截止前/等于/后、未知类别拒绝；断言手机不受气泡暂停影响。
- [ ] 运行 `cd native && swift test --filter NotificationPolicyTests`，确认缺失类型导致失败；.NET `dotnet run --project windows/QuotaBar.Core.Tests` 同样先失败。
- [ ] 实现schema=1模型、默认值、阈值合法范围、安全解码及纯decision；category与kind分离，新增独立priority。
- [ ] 重跑相同命令，fixture全部通过；非法schema默认不远程发送。
- [ ] 审阅后提交 `feat: define notification category policy`。

### Task 2: 偏好与历史迁移

**Files:** 双端NotificationPolicy、现有偏好存储/ExperienceStore/BarkDeliveryStore；migration-cases.json及两端NotificationPolicyTests。

**Interfaces:** `NotificationPolicyMigration.migrate(legacy: LegacyNotificationPreferences) -> NotificationPolicyPreferences`；存储提供loadOrMigrate，只在原子保存成功后选用新策略。Legacy包含presentation、pausedUntil、recovery、celebration、bank、updatesReminders、barkEnabled。

- [ ] 写迁移fixture：4种旧mode×Bark开关×业务开关，尤其recovery=false/celebration=true；新两类始终关闭；二次加载不再导入旧值。
- [ ] 添加保存失败/损坏新schema/保留Key与generation/旧Bank和Bark收据不重发断言，先运行并确认失败。
- [ ] 实现规格迁移映射及原子切换；旧键只读兼容，收据保留旧identity。
- [ ] 运行Task1两端命令，全部通过；模拟保存失败仍保持旧行为。
- [ ] 提交 `feat: migrate legacy reminder preferences`。

### Task 3: 三渠道独立路由与取消

**Files:** 两端AppNotificationRouter、BarkNotificationController/BarkDeliveryStore、NotificationPresentation及对应原生router/Bark测试。

**Interfaces:** 路由注入 `policyProvider: () -> NotificationPolicyPreferences`；传送任务携带policyRevision；事件创建冻结eligibleChannels和policyRevision，后续只删减；渠道投递键 `NotificationDeliveryIdentity(eventID, reminderGeneration, channel)`；发送前检查decision与业务valid，回执不阻断其他渠道。

- [ ] 用假传输写失败测试：气泡已显示手机仍发送、手机接受不吞系统、Bank一渠道接受不使另一渠道valid失效、关闭期间事件开启后不出队、单元格禁用只取消对应渠道、关后重开不补发、晚到回调不复活、账号切换取消、预览不发手机。
- [ ] 增加手机安全存储阻塞/拒绝时启动与桌面继续工作的测试；Key读取移出启动主线程，配置UI只在需要时异步读取。
- [ ] 确认现有实现至少在独立策略/阻塞用例失败后，接入策略与渠道收据。保留Bark unknown防重机制；已接受不承诺撤回。
- [ ] 运行 `cd native && swift test`、`dotnet run --project windows/QuotaBar.Core.Tests`；Windows原生测试在Windows执行 `dotnet run --project windows/QuotaBar.Windows.Tests`。以各实际退出码为准。
- [ ] 提交 `feat: route reminders by category and channel`。

### Task 4: 恢复、Bank与更新接线

**Files:** 双端QuotaExperience、QuotaExperienceController、QuotaUpdateController.swift/UpdateController.cs及Experience/Update/router测试。

**Interfaces:** 事件构造必须传入category；Bank按stage拆成bankExpiring72h/24h；更新保留版本ID、skip/snooze；恢复检测条件为celebration或任一恢复/耗尽渠道被选择，内部恢复不隐式通知。

- [ ] 先写失败测试：动画开启但矩阵全关不通知；手机恢复单开可生成；Bank直接进入24小时只发24，72→24各一次；关闭更新自动检查不妨碍手动检查。
- [ ] 添加更新skip/snooze取消全部渠道、延后结束由后续合法检查触发而非补发的测试。
- [ ] 接入分类，移除旧业务总开关权威地位；保留恢复确认、Bank当前存量验证与120秒事件时效。
- [ ] 执行Task3双端命令并通过；阶段一核心行为可独立验收，但完整需求仍未完成。
- [ ] 提交 `feat: classify recovery bank and update reminders`。

### Task 5: 偏低与耗尽状态机

**Files:** 新增双端QuotaWarningEngine与warning-cases.json；接入两端QuotaExperienceController及持久化存储；新增QuotaWarningTests。

**Interfaces:** Swift `QuotaWarningEngine.observe(_ observation: QuotaObservation, threshold: Int, now: Date) -> [QuotaWarningEvent]`，`resetBaseline()`；C#等价Observe；WarningEvent含category/periodIDs/threshold/incidentID。每周期状态保存lowNotified、exhaustionIncident及恢复后重新武装状态。

- [ ] 共享样例断言：21→20发偏低；20→19不再发；1→0发耗尽；21→0只耗尽；首次0无提醒；缺失不当0；过期/乱序拒绝。
- [ ] 覆盖双周期合并、阈值修改、首次启用、新周期、固定锚点连续30秒漂移及59/60秒边界、回退重建基线、重启不重复、新周期不吞恢复事件、恢复通知与庆祝全关时确认恢复后再耗尽。
- [ ] 运行 `cd native && swift test --filter QuotaWarningTests` 和.NET Core测试先失败；实现纯状态机、持久化和controller接线。
- [ ] 重跑并通过；保存失败不发送，账号切换清除旧epoch，不引入独立轮询计时器。
- [ ] 提交 `feat: add low and depleted quota alerts`。

### Task 6: 设置界面、迁移提示与本地化

**Files:** 两端原生设置组件、NotificationSettingsView.swift、BarkSettingsView.swift；原生UI测试及截图证据文档。

**Interfaces:** 每单元格调用单一 `setRule(category, channel, enabled)` 保存策略并递增revision；总开关 `setChannelEnabled(channel, enabled)`；阈值 `setLowRemainingThreshold(value)`；均持久化成功后发布变更，失败回滚控件并提示。

- [ ] 使用frontend-ui-visual-gate完成现有设置风格内的矩阵/窄窗口卡片视觉审阅；不把本文档视为视觉批准。
- [ ] 写原生UI失败测试：18单元格、Bank展开、阈值10/20/30、重启保留、失败回滚、总开关不抹规则、手机未配置/系统拒绝提示、三语言可访问标签。
- [ ] 实现集中提醒设置及独立外观区，系统授权只由显式动作发起，Bark测试只发示例，安全存储不可用不阻塞页面。
- [ ] 双端原生执行UI测试，分别检查浅深色/三语言/窄窗口截图，无重叠截断；人工确认气泡预览和设置即时生效。
- [ ] 提交 `feat: expose notification category settings`。

### Task 7: 整体验收和交付

**Files:** docs/PROJECT_PROGRESS-standalone-app.md、功能说明、当前spec/plan验收勾选；看板仅通过utility。

- [ ] 运行 `./governance check all`，若dotnet不在PATH使用已安装SDK路径，不跳过检查。
- [ ] 在精确产品提交上运行macOS/Windows原生CI，保留run与源码对应；分别执行安装候选后的设置持久化、真实事件/气泡/系统权限验证（安装需对应授权）。
- [ ] 手机先用模拟传输验证协议，再由用户授权主动发送测试并确认iPhone展示；若未做，记录“未做手机设备验收”，不把accepted标为送达。
- [ ] 回归更新下载/取消/skip/snooze、账号隔离、运行时启动退出；独立审查并修复实质问题。
- [ ] 更新路线图/看板：已实现、本地测试、原生CI、设备、发布分别记录；无发布授权则停止在候选交付，不改版本或公开资产。

## 实施顺序与当前状态

用户确认当前会话原生实施，视觉先选B后更正A，最终采用A紧凑矩阵。

| 任务 | 状态与证据 |
| --- | --- |
| 1 分类契约 | 已实现；54组共享矩阵、实际队列优先级、损坏安全关闭通过 |
| 2 迁移 | 已实现；128组合、原子保存失败、旧数据单次导入、损坏提示通过 |
| 3 路由 | 已实现；创建快照、只删减、独立渠道接受、取消/同generation不重发、新generation可发通过 |
| 4 现有事件 | 已接线恢复/Bank72及24/更新；Bank静默库存及启用待基线持久化通过，原生Windows更新接线测试待CI执行 |
| 5 新预警 | 已实现；18组共享序列、直接耗尽/双周期/未知/重启/固定锚点/阈值不重武装通过 |
| 6 设置 | A矩阵双端实现，18单元格/阈值/总开关、六张macOS原生渲染及真实文本高度断言通过；Windows原生交互/渲染待CI |
| 7 交付 | 本地完整治理182Core+125AppKit及.NET Core、Windows跨编译通过；候选打包与原生CI继续，不安装/合并/公开发布 |

独立代码审阅发现3项P2及损坏提示均已失败回归修正，并复核无新增P1/P2；补充Bank不完整库存基线、同generation按渠道不重复投递的真实回归亦通过。执行日志在本计划专属.superpowers工作区；不能把交叉编译标为Windows设备验收。
