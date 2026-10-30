# Local Message Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 双端以C列表详情消息中心替代未读入口，持久保存全部真实提醒与已读状态，完成验证、候选打包及草稿交付。

**Architecture:** 独立Core消息档案与投递队列分离，原子JSON记录UTC毫秒及消息逻辑身份。路由记录业务事件和显式/详情阅读状态；原生窗口只查询档案、打开当前页面，不重新投递历史。

**Tech Stack:** Swift/AppKit/Foundation、C#/.NET10/WPF、已有JSON存储模式，无新依赖。

**Spec:** docs/superpowers/specs/2026-10-26-local-message-center-design.md

## Global Constraints

- C最终修正版；双端原生、三语言、浅深色；使用现有QuotaBar图标。
- 历史页含全部真实消息，未读是其中子集；多渠道合并，测试/预览不入历史。
- 用户主动打开详情自动已读；初始载入/页签切换/重建不自动读取；不得连锁读取下一条。
- 本地message-center.json，UTC Unix毫秒；不保存凭据、回调或delivery token。
- 不按32条/24小时/账号切换自动删除；重启历史零额外投递。
- 未读状态保存失败不报告成功；损坏/读失败保留原文件，提供明确错误及重试，临时记录明确标识。
- 普通提交不改版本；草稿PR、双端候选，不合并或公开发布；WindowsCI不等同用户设备通过。

## Review Focus

- 自动已读导致过滤行后程序自动选中下一行：Task3/4测试只读用户点中的一条。
- 仅系统/手机或气泡暂停的真实消息漏记录：Task2实际路由测试。
- 损坏/锁定历史被空数据覆盖或已读虚假成功：Task1及Task3/4失败恢复测试。
- 账号epoch/应用停止取消实时队列时误删历史：Task2重启/取消回归。
- 大量历史导致布局与保存耗时恶化：Task1一万条保存/恢复，Task3/4虚拟化或分页及长文测试。

---

### Task 1: Shared message archive contract and durable stores

**Files:** Create native/Sources/QuotaCore/MessageCenter.swift, windows/QuotaBar.Core/MessageCenter.cs, native/Tests/QuotaCoreTests/MessageCenterTests.swift, windows/QuotaBar.Core.Tests/MessageCenterTests.cs, contracts/notifications/message-center-cases.json; modify Windows Core.Tests Program.cs fixture registration.

**Interfaces:**
- Produces MessageCenterKey(id,generation,epoch?) Codable/record hashable; MessageCenterRecord(key,category,title,body,createdAtMilliseconds,readAtMilliseconds?,channels).
- Produces MessageCenterStore(url/path): records sorted descending, unreadCount, error, hasUnpersistedMessages; append(record)->Bool, markRead(key,atMilliseconds)->Bool, markAllRead(atMilliseconds)->Bool, reload()->Bool. First snapshot immutable, duplicates merge channels without resetting read. Optional explicit bulk import for10k fixture without O(N) single-write test setup.
- On failed load, pending new messages may be visible as volatile overlays; reload merges them only after original document successfully loads. Failed read mutations do not apply. No hidden deletion limit.

- [ ] Write fixtures and tests for multi-channel dedup, generation/epoch keys, sort/read/restart, no expiry pruning, corrupted file protection, write failure and reload,10k records, UTC cross-language roundtrip.
- [ ] Run Swift MessageCenterTests and dotnet Core suite; observe missing-type/behavior failures, then implement store and pass all named cases.
- [ ] Commit core/models/fixtures after focused green.

### Task 2: Router capture, persistent unread counters and safe actions

**Files:** Modify both AppNotificationRouter files, both QuotaExperienceController files, native StandaloneCoordinator.swift and Windows Coordinator.cs; test native MessageCenterRoutingTests.swift and Windows NotificationMatrixTests.cs/Program.cs.

**Interfaces:**
- Consumes Task1 MessageCenterStore and keys/records.
- Produces router bindMessageCenter/BindMessageCenter(store), messageHistory/MessageHistory, messageUnreadCount/MessageUnreadCount, currentMessageEpoch/CurrentMessageEpoch, markMessageRead/MarkMessageRead(key)->Bool, markAllMessagesRead/MarkAllMessagesRead()->Bool, retryMessageStorage/RetryMessageStorage()->Bool, openMessageLatest/OpenMessageLatest(record) and UI change observers.
- Swift observer token UUID registration/removal; Windows event MessageCenterChanged. Existing unread presentation APIs remain for live routing tests but production counts use archive.
- Record category-bearing business messages before per-channel presentation, evaluating configured category+enabled channels independent of bubble pause. No tests/previews. Legacy category-less real kinds mapped for fallback behavior. Bind production stores before receiving events. Current epoch comes from persisted engine state.

- [ ] Add failing actual-router tests: all five categories, system/mobile-only, pause records, all-off excluded, test excluded, multichannel one record, click/ack read persisted, stop/cancel retains archive, restored history dispatches no sends.
- [ ] Integrate only archival capture; retain existing delivery receipt and channel eligibility logic. Historical actions open current details/update settings with no old token.
- [ ] Run relevant Swift routing plus .NET and Windows test build; record native Windows runtime pending until CI.
- [ ] Commit integration after focused green.

### Task 3: macOS C message center and native interactions

**Files:** Create native/Sources/CodexQuota/MessageCenterPanel.swift and MessageCenterView.swift, native/Tests/CodexQuotaTests/MessageCenterSettingsTests.swift; replace NotificationUnreadPanel use and update all native entry labels/help copy. Remove obsolete panel after no references remain.

**Interfaces:**
- Consumes Task2 router archive, read methods and safe current-page actions.
- Produces MessageCenterPanel.show(router,language), close(); MessageCenterView native segmented tabs + virtualized NSTableView + detail panel, default900×600, min680×440, <760 single-pane/back layout.
- Selection is initially nil. Only user selection opens details and marks that exact key read; refresh preserves detail and does not select a successor. Tabs/refresh guarded against read callbacks.

- [ ] Write actual-window tests for two tabs/empty/count, one-row auto-read/no cascade, history read row remains, all-read, selected details retention on new messages, errors/retry, narrow back layout, three languages/themes and10k virtualized list.
- [ ] Run tests RED, implement C layout with existing icons, then focused GREEN and six rendered screenshots.
- [ ] Commit macOS UI/entry updates.

### Task 4: Windows C message center and native interactions

**Files:** Create windows/QuotaBar.Windows/MessageCenterWindow.cs, Windows UI test MessageCenterNativeTests.cs; update Coordinator and entry labels, remove obsolete NotificationUnreadWindow after references removed.

**Interfaces:**
- Consumes Task2 same store/router contract.
- Produces MessageCenterWindow(router,copy,dark) with top tabs, virtualized ListBox, detail and responsive Grid; <760 single-pane/back; subscribe/unsubscribe change event on window lifecycle.
- Programmatic ItemsSource/selection restoration must not mark next row read. Auto read only on user row activation; selection cleared from unread list while detail remains.

- [ ] Add native-window tests for Task3 behaviors plus125/150/200% logical scaling, long translated labels, failed read/write recovery, keyboard interaction.
- [ ] Cross-build and .NET suite; push red native UI baseline if needed to observe failure, then implement and observe native CI green. Do not claim Windows execution from cross-build.
- [ ] Commit Windows UI/entry updates.

### Task 5: Whole validation, review and candidate delivery

**Files:** Update docs/NOTIFICATION_SETTINGS.zh-CN.md, docs/PROJECT_PROGRESS-standalone-app.md, message center validation evidence, draft PR60. Use existing candidate build/verify/install scripts and CI workflow.

**Interfaces:** Consumes Tasks1–4 product. Produces tested dual candidates, source/snapshot/hash evidence and draft PR download links.

- [ ] Run governance check all; inspect exact192+new Core/AppKit counts, installer fixtures, .NET behavior and Windows builds. No product version change.
- [ ] Fresh whole-branch reviewer checks full feature diff against updated approved spec; fix Important/Critical with red/green and rerun affected suite.
- [ ] Push with normal hooks, verify both native CI and candidate provenance; retain actual failed-run evidence if retries are needed.
- [ ] Serial Mac packaging after all Swift/push hooks finish; source/hash/signatures/startup/DMG checks and authorized local candidate test/install. Do not run packaging isolation concurrently with Swift builds.
- [ ] Download Windows ZIP, CRC/SHA/provenance/source snapshot/setup verification. Inspect actual Windows UI renders. Both native jobs must pass for delivered build, user device results remain distinct.
- [ ] Update cohesive draft PR with latest dual downloads; update roadmap/board and validate; audit every spec requirement before goal complete. No merge/public release.
