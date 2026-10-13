# Update Notifications Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement platform-specific HTTPS release discovery and native update reminders on macOS and Windows.
**Architecture:** Shared JSON fixtures specify a stable feed; independent Swift/C# pure policies validate it and deduplicate reminders. Platform controllers fetch asynchronously and render native settings. A serialized Pages workflow generates a feed only from verified public releases.
**Tech Stack:** Swift/Foundation/AppKit/UserNotifications; .NET 10/HttpClient/WPF/NotifyIcon; Python/GitHub Actions/Pages.
**Spec:** docs/UPDATE_NOTIFICATIONS.zh-CN.md plus user-selected visual direction A.

## Global Constraints
- No automatic download/install; no product version edits; no public deployment in this task.
- Keep existing controls and append a compact update section; native checkboxes, inline version status and actions.
- macos-arm64 and windows-x64 stable entries only; no draft/prerelease or unsupported OS.
- Native reminders are optional; app UI remains usable without notification permission.
- HTTPS allowlisted release pages, bounded networking, no GitHub credentials in clients.

## Review Focus
- Platform release skew or missing assets cannot produce a false update.
- 0.10.0 must compare greater than 0.9.0; malformed versions are rejected.
- Concurrent wake/network/timer events must not duplicate requests or reminders.
- Disabling reminders, skip and snooze persist across restart.
- Failed requests or notification delivery cannot become a false “up to date” result.

## Tasks
- [x] Feed contract + Swift/C# parser/policy tests: incompatible OS, invalid links, version boundaries, snooze/skip/restart. Observe RED before implementing.
- [x] macOS asynchronous checker and A settings/menu + local notifications; run Swift suite and native visual fixture.
- [x] Windows checker and A settings/menu + NotifyIcon reminders; run Core tests/cross compile, record native Windows test boundary.
- [x] Feed generator and serialized Pages workflow; test partial releases, drafts, missing proof assets and monotonic platform selection; hook policy checks.
- [x] Review all changes, run full governance and builds, update roadmap/board; leave unpushed and undeployed unless authorized.

## Visual decision
User selected A after viewing A/B/C. Preserve existing settings controls, account actions, quota card, app icon, themes and three languages. Add only a separator, update checkboxes, version/status row and inline actions. Settings must grow/scroll on small screens; keyboard-native controls and system colors. Concept versions/icons were illustrative.


## Execution ledger
- Core policy and both adapters implemented; parser and persistence checks pass.
- Ruling: system reminders default off — avoid unsolicited OS permission prompts; auto discovery stays on.
- Ruling: no Pages deployment without separate activation — preserve current no-publication scope; workflow is explicit opt-in.
- Review: fixed stream IOException handling, notification/snooze races, shutdown cancellation, delivered-event dedup and release proof/checksum matching.
- Integrated macOS short-settings test passes with actions visible; Windows native fixture added but needs CI.
- Current live feed generation verified platform skew; all networking is independent from quota collection.

- Final evidence: clean-source 634e5b7, CI 38420826360 passes on both platforms; installed macOS candidate signature/binary/ready-state and native layout verified. Pages activation and real OS reminder acceptance remain explicitly outside this completed implementation validation.
