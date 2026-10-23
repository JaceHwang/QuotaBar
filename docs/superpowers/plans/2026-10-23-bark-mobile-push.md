# Bark Mobile Push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 为 QuotaBar 接入可独立启用、安全配置、真实提醒去重的 Bark 手机推送。

**Architecture:** 在统一提醒入口按桌面与手机分流；手机拥有独立队列、持久化尝试收据和配置 generation。Core 提供两端一致的数据、编码及收据规则；原生层负责安全凭据、HTTP、生命周期与第五设置页。手机成功与桌面实际展示共享一次语义回执，但不互相阻止发送或读取桌面未读。

**Tech Stack:** Swift 6 / Foundation / AppKit / Security / URLSession；.NET 10 / WPF / HttpClient / Windows Credential Manager；不增加第三方依赖。

**Spec:** `docs/superpowers/specs/2026-10-23-bark-mobile-push-design.md`

## Global Constraints

- 自动手机推送默认关闭；无 Key 无法启用；保存 Key 不自动启用或发送。
- 只转发有效恢复、Bank、更新；桌面示例不自动转发；手机测试仅用示例。
- 固定 `https://api.day.app/push`，HTTPS POST JSON；不跟随重定向，不绕过 TLS。
- 请求上限 3000 编码字节，响应上限 65536 字节，总超时 10 秒，串行队列最多 32；失败不自动重试。
- 成功必须 HTTP 2xx 且 JSON code=200；超时/不明确响应只报告失败或结果未知，不声称手机已显示。
- Key 仅用 Keychain/Credential Manager；测试注入 fake，不访问真实凭据或网络；不写日志、URL、偏好或收据。
- 第五页追加在更新后；保留更新 index=3 / Windows key=updates 与旧四页测试 fixture。
- 三语言、浅深色、键盘及读屏沿用现有苹果风格；不生图。
- 额度不变时桌面气泡持续显示的现有行为保留。
- 不改产品版本，不合并 main，不公开发布，不发真实手机推送。
- 用户已授权计划后直接实施及多智能体并行开发测试；不再设计划批准暂停。复用当前隔离 worktree，分支 `codex/feat/bark-mobile-push`；root 串行提交，子代理不操作 Git index。

## Review Focus

1. 桌面 off、隐藏、暂停、锁屏不能吞掉手机事件；任一渠道成功不能吞掉另一渠道。
2. 启用、更换 Key、重启及同 ID 晚到回调不能重播旧消息或污染新配置。
3. Key 保存失败保留原配置；清除即关闭、取消；测试不碰用户凭据。
4. HTTP 重定向、超大响应、超长 Unicode、业务失败不泄漏 Key、阻塞刷新或伪报成功。
5. 更新 snooze 明确重新布防允许新 generation；普通渠道切换不产生新 generation。

## Frozen interfaces and ownership

Task 1 owns only `native/Sources/QuotaCore/Bark*.swift`, Core tests, `windows/QuotaBar.Core/Bark*.cs`, `Preferences.cs`, `ExperienceNotification` metadata on both ends, Windows Core tests and `contracts/bark/`.
Task 2 owns `native/Sources/CodexQuota/` and `native/Tests/CodexQuotaTests/`.
Task 3 owns `windows/QuotaBar.Windows/` and `windows/QuotaBar.Windows.Tests/` (use actual existing native test project if differently named).
Root owns documents, integration-only fixtures/scripts, verification and Git. No overlapping edits without root coordination.

All three implementers read this section and the approved spec. Task 1 must provide the following API; language conventions translate Swift lowerCamelCase to C# PascalCase. Core may add overloads but must coordinate breaking changes before editing:

- `BarkPreferences`: Codable/record; schema 1, enabled false, configurationGeneration random non-secret string. Swift `init(enabled: Bool = false, configurationGeneration: String = UUID().uuidString)`; C# init properties `Enabled`, `ConfigurationGeneration`; `Validated()` / `validated()`.
- `BarkEventIdentity`: id and generation strings, Equatable/Hashable or record; init(id:generation:) default generation `initial`.
- `ExperienceNotification`: additive `reminderGeneration` / `ReminderGeneration` optional initializer trailing parameter, default `initial`. Update producer captures snooze-until as `snooze:<UTC epoch milliseconds>` before shared shown clears it. Recovery/Bank retain default.
- `BarkPayload`: static `isValidDeviceKey(_ key: String) -> Bool` / `IsValidDeviceKey(string)`; `encode(deviceKey:title:body:) throws -> Data` / `Encode(string deviceKey,string title,string body) -> byte[]`. Trim outer whitespace; reject empty, internal whitespace/control, URL delimiters `/`, `\\`, `?`, `#`, `://`, >512 UTF8 bytes. JSON keys exactly device_key/title/body/group/level, group QuotaBar, level active. No URL field in v1. Unicode grapheme-safe truncation against encoded byte limit.
- `BarkResponse`: enum accepted/rejected/unknown; static `classify(statusCode: Int, body: Data)` / `Classify(int,byte[])`, including response size check. Transport failures mapped to sanitized category by platform, never exception raw text.
- `BarkDeliveryStore`: init(url: URL) / `(string path)`; `needsBaseline` / `NeedsBaseline`; `hasPersistenceError` / `HasPersistenceError`; synchronous serialized `reserve(identity: BarkEventIdentity, now: Date, protected: Set<BarkEventIdentity> = []) -> Bool` / `Reserve(identity,now,IReadOnlySet<BarkEventIdentity>? protectedIdentities=null)`; `markAccepted(identity:now:)` / `MarkAccepted`; `establishBaseline(identities:[BarkEventIdentity],now:) -> Bool` / `EstablishBaseline`. Reserve atomically persists attempt before returning true; duplicates/persistence failure/capacity return false. Corrupt file preserved, needsBaseline true; establishBaseline suppresses known current identities and clears recovery mode. If corrupt and no baseline yet reserve suppresses first encountered identity, never sends it. Max256/30days, protect live identities; if no safe eviction refuse new admission. No body/Key/raw response stored.
- Platform controllers own their injectable SecretStore and transport APIs; do not require counterpart platform imports. Controllers must expose enqueue(message,valid,accepted), cancel(id), cancel(epoch), stop, settings operations/status, and suppression for already-known current identities on enable/config change.

## Task 1: Shared Core payload, preferences and durable mobile receipts

**Files:** Create Bark*.swift in QuotaCore; Bark*.cs in QuotaBar.Core; modify both ExperienceNotification models and Windows Preferences; create matching Core tests and `contracts/bark/` fixtures.

**Consumes:** Frozen interfaces, approved spec. **Produces:** The frozen API and shared sanitized JSON scenarios for payload/receipt behavior.

- [x] Add failing tests for defaults/migration, key validation, Unicode/emoji/escaping and 3000-byte boundary, response status/business/size checks, restart dedup, corrupt preservation, atomic failure, baseline suppression, 256 capacity and protected live IDs.
- [x] Run focused Swift Core and Windows Core tests and record meaningful RED evidence before implementation.
- [x] Implement minimum Core types; malformed Bark preferences must not discard unrelated existing preferences. No platform credentials or HTTP in Core.
- [x] Run both Core suites against shared fixtures, self-review and report commands/results/changed files to root. Root serializes the verified Core commit.

Commands: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path native --filter Bark`; `PATH="$HOME/.local/share/quotabar-dotnet:$PATH" dotnet run --project windows/QuotaBar.Core.Tests` (confirm existing test entry point).

## Task 2: macOS secure transport, independent routing and fifth settings page

**Files:** Create `BarkSecretStore.swift`, `BarkPushClient.swift`, `BarkNotificationController.swift`, `BarkSettingsView.swift` under CodexQuota; modify `AppNotificationRouter.swift`, `QuotaUpdateController.swift`, `StandaloneCoordinator.swift`, `QuotaSettingsShellView.swift`; add native tests.

**Consumes:** Task1 frozen API. **Produces:** Mac fully wired feature with fake-injectable stores/transport and no real test side effects.

- [x] Add failing fake-store/transport tests: desktop off/hidden/paused still sends; preview exclusion; two-channel arrival permutations and no double shared receipt; account/config/skip/snooze cancellation, old completion isolation, no backlog when enabling.
- [x] Add tests for permission-independent phone, queue limits/expiration, explicit test while auto off, failed-save retaining config, clear/disable cancellation, draft persistence and old four-page fixture + fifth-page navigation.
- [x] Implement Keychain generic secret adapter, fixed URLSession endpoint/no redirects/10s/bounded streaming response, async serial queue32, durable attempt-before-send/no retry and sanitized statuses. Inject fakes in ALL coordinator tests; never read actual Keychain in tests. Do not initialize a real store merely to render fixtures.
- [x] Route Bark before desktop off gate. Track mobile vs desktop success independently, aggregate shown once. Include update snooze generation. Enabling/config changes suppress current known events and do not scan/replay. Cancel mobile before native teardown.
- [x] Implement fifth page with NSSecureTextField, no secret readback, save/clear/test, status/timestamp, three languages and existing card/row helpers. Preserve editing draft through refresh/rebuild. Unconfigured cannot enable, save does not auto-enable/test.
- [x] Run native focused tests then full Swift tests; render five pages in three languages/two themes plus narrow window, inspect images, record gaps. Root serializes commit after scoped review.

Commands: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path native --filter Bark`; full `swift test --package-path native` (same DEVELOPER_DIR). Use an independent scratch path if concurrent Swift compilation conflicts.

## Task 3: Windows secure transport, independent routing and fifth settings page

**Files:** Create BarkSecretStore.cs/BarkPushClient.cs/BarkNotificationController.cs/BarkSettingsView.cs in QuotaBar.Windows; modify AppNotificationRouter, Coordinator, UpdateController and SettingsWindow; extend existing Windows native UI test harness.

**Consumes:** Task1 frozen API. **Produces:** Windows feature parity, cross-build and native test coverage.

- [x] Add failing native fake tests matching Task2: independence, shared once receipt, restart dedup, cancellation/generation, skip/snooze, test-only example and save/clear/draft/settings states.
- [x] Implement current-user Credential Manager generic P/Invoke adapter without new packages, injectable fake; HttpClientHandler AllowAutoRedirect=false, timeout10s, ResponseHeadersRead + bounded stream; never persist/log raw Key or exception text.
- [x] Implement controller/router/update semantics matching Task2 and approved spec, preserving NotifyIcon serial updates and persistent local bubbles. Current reminder generation captured before shown callback clears snooze.
- [x] Append mobile page after updates, PasswordBox draft preserved, localized secure config/status/test controls and accessibility. Update all temp-data test coordinators to fake stores; no real CredRead/CredWrite in native tests.
- [x] Run native tests on Windows CI and local cross-build; report distinction. Provide five-page three-language/two-theme screenshots in native harness, plus narrow scrolling checks. Root serializes commit after scoped review.

Commands: `PATH="$HOME/.local/share/quotabar-dotnet:$PATH" dotnet build windows/QuotaBar.Windows/QuotaBar.Windows.csproj --no-restore` (restore if required); actual Windows native test entry point in `.github/workflows/ci.yml`. macOS cross-build is not native device evidence.

## Task 4: Cross-platform integration and independent review

**Files:** Focused integration tests/scripts only where gaps found; README.md/README.zh-CN.md, privacy and troubleshooting documents using existing paths.

- [x] Root reconciles three reports against code and frozen interfaces. Add regression tests before any integration fix; do not weaken existing tests.
- [x] Obtain fresh scoped reviewer for each task (spec+quality), and a separate most-capable whole-feature reviewer; resolve load-bearing findings, run relevant tests and record re-review.
- [x] Verify mobile attempt and desktop receipt separation, update pure-phone notified behavior, malformed prefs, crash boundary, no Key in diagnostics/receipts, no automatic example push.
- [x] Document external HTTPS data flow to Bark/APNs, user setup, difference between service accepted and phone shown, no retry, clear/disable, unknown results, OS secure-store errors and manual phone test.
- [x] Run `git diff --check`, `./governance check all`, complete Swift/Core/native build checks. Record exact unrun native/device items.

## Task 5: Candidate, CI and delivery record

**Files:** `docs/PROJECT_PROGRESS-standalone-app.md`, platform acceptance record, approved spec/this plan; board through utility only.

- [x] Check governance, commit verified changes by ownership, build macOS candidate with pinned official runtime and verify signature/source snapshot/DMG; isolated startup test uses temp data and no configured Bark.
- [x] Push only feature branch and create Draft PR targeting dependency branch or correct main base after checking live state; attach PR. Never merge/publish. Run existing native CI and inspect all checks. Fix CI failures with tests and repeat only relevant checks.
- [x] Verify Windows candidate if workflow produces it; record which build/CI/device checks ran. No real phone pushes or Key extraction; user config/test remains manual.
- [x] Update roadmap and board with implemented/local/CI/device/released distinctions; preserve previous installation unless user requests this candidate install. Deliver plan + implementation status and concise phone setup instructions.
