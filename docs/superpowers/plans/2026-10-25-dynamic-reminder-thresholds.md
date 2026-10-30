# Dynamic reminder thresholds implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development for independent Bank and low-warning core tasks; coordinator implements shared policy/routing/UI and integrates reviews.

**Goal:** Deliver approved A editable multi-threshold reminders with merged Bank and independent column select-all.

**Architecture:** Keep legacy category serialization; extend optional policy threshold lists and per-hour Bank channels, add exact threshold metadata to messages/snapshots. Core detectors consume normalized lists; native views show five grouped rows and editable wrapping chips.

**Tech Stack:** Swift6/AppKit/QuotaCore, .NET10/WPF.

**Spec:** docs/superpowers/specs/2026-10-25-dynamic-reminder-thresholds-design.md

## Global constraints

- Approved A; master names 气泡通知 / 系统通知 / 手机推送通知. Rows depleted/restored/low/Bank/update.
- Low1–99%, Bank1–8760h, max32 unique descending values; explicit empty list means disabled events. No history replay.
- Preserve legacy scalar, channel mappings, receipts, threshold-specific eligibility and independent masters.
- No product version change, real phone send, merge or public release. Build isolation and other Swift work must not overlap.

## Review focus

- Different old72/24 channel rules must remain different until a user explicitly unifies them.
- New/removed thresholds must neither replay nor allow stale queued notifications.
- One low/Bank sample crossing multiple levels coalesces while persisting consumed levels.
- Empty/invalid/missing lists and old state files must be distinguished.
- Multiple chips must fit/wrap in every language/theme without blocking matrix controls.

## Task1: Policy and exact threshold routing (coordinator)

Files: both NotificationPolicy implementations/stores/tests, ExperienceNotification, NotificationDeliverySnapshot, platform AppNotificationRouter.
- [x] Add failing decode/default/migration/mixed-channel/snapshot tests.
- [x] Add optional lowRemainingThresholds, bankExpiryHours, bankThresholdChannels; effective normalized list/channel helpers. Keep schema1/scalar fallback and legacy categories.
- [x] Add optional reminderThreshold to messages and snapshots; exact policy checks on queued and mobile deliveries. Test removed threshold and channel non-expansion.

## Task2: Dynamic Bank detector (Bank implementer)

Own only native/Sources/QuotaCore/QuotaExperience.swift, native/Tests/QuotaCoreTests/QuotaExperienceTests.swift (or new DynamicBankTests.swift), windows/QuotaBar.Core/QuotaExperience.cs, windows/QuotaBar.Core.Tests/ExperienceTests.cs (or new DynamicBankTests.cs plus registration in Program.cs ONLY coordinate if needed), and a new contracts/notifications/dynamic-bank-cases.json.

Interfaces: append defaulted bankThresholds:[Int]=[72,24] to Swift observe and bankEventsAreCurrent; C# Observe/BankEventsAreCurrent optional IReadOnlyList<int>? bankThresholds=null. Preserve old callers. suppressBankStages accepts arbitrary valid hours. Event.stage is exact hour. Preserve legacy receipt.stage ordering, coalesce to most urgent current band, complete-inventory baseline and bounds; receipt retention supports the configured horizon.
- [x] Write and observe failing dynamic fixtures; implement and run Swift/.NET core tests in isolated scratch copies to avoid shared builds.
- [x] Return interfaces, changed paths and evidence; do not commit or alter policy/UI files.

## Task3: Dynamic low-warning detector (warning implementer)

Own only both QuotaWarningEngine implementations, their tests, contracts/notifications/warning-cases.json and a new dynamic-warning fixture if needed. Do not edit policy or UI or Bank engine.

Interfaces: Swift observe(_ observation:QuotaObservation, thresholds:[Int], now:Date); retain scalar overload. C# Observe(QuotaObservation observation,IReadOnlyList<int> thresholds,DateTimeOffset now) and retain scalar overload (match existing argument order). Empty disables low only, not depletion. Preserve consumed per-threshold state and stable event.threshold/incidentID, restart baselines and internal depletion recovery. List edits baseline added thresholds without rearming existing consumed ones.
- [x] Write failing multi-level/coalescing/edit/legacy-state fixtures, implement and run isolated Swift/.NET core tests.
- [x] Return interfaces, changed paths and evidence; do not commit or edit policy/UI/Bank files.

## Task4: Controllers and native A UI (coordinator)

Files: both QuotaExperienceController, NotificationMatrixSettingsView, UI tests and copy.
- [x] Pass effective lists into detectors, group Bank by exact stage and attach reminderThreshold. Suppress newly enabled Bank hours until a complete inventory; validate pending events against current lists.
- [x] Replace scalar editor/duplicate Bank rows with wrapping editable chips; validated add/edit/delete with numeric units and empty state. Migrate channels through helper methods, expose mixed state.
- [x] Rename masters and add three compact per-column Select all controls; never change other columns/masters/thresholds on select-all.
- [x] Add failing UI/controller integration tests before implementation, run native renders and keyboard/accessibility tests.

## Task5: Review, verification and local delivery

- [ ] Independent review for each core task and whole branch; fix material findings with failure regressions.
- [ ] Full governance, shared contract parity and Windows native UI/CI. Record any incomplete remote/platform checks.
- [ ] Commit clean candidate sources; serialize push checks and Mac build/isolation. Verify provenance, signatures, startup and fresh-default policy, then transaction-install on this Mac preserving account/settings and original chosen values.
- [ ] Update roadmap/board/PR and acceptance boundaries; no real phone notification, merge or release.
