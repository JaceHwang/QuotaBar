# QuotaBar Windows Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task in the current session.

**Goal:** Windows独立版实现当前macOS功能，托盘按用户选择仅图标，额度在提示和浮窗。

**Architecture:** UI-independent Core implements decoding, state, settings and runtime session. Native WPF/NotifyIcon UI owns system lifecycle and presentation. Self-contained packaging bundles the pinned official runtime and a recoverable per-user installer.

**Tech Stack:** .NET 10 LTS, WPF, WinForms NotifyIcon, official Codex 0.144.1.

**Spec:** [Windows design](../specs/2026-10-12-windows-standalone-design.md)

## Global Constraints

- Windows 11 x64; no preinstalled .NET/Codex requirement.
- Preserve independent credentials; no host UI scanning, account copying or automatic Bank actions.
- Missing data remains unavailable; 60s refresh, 20s timeout, 300s maximum backoff.
- Tray icon only; quota in tooltip and floating button. Floating visibility is separate and persists.
- Existing QuotaBar visuals; hover-only close control, no width jump, separate hit region.
- No product version edits or public release in this implementation task.

## Review Focus

- Late quota/account responses after logout must not revive old data.
- Cancel/login timeouts and transport restart must not hang or loop indefinitely.
- Invalid preferences or disconnected monitors must retain an accessible window.
- Closing a floating-origin locked detail must leave tray/runtime alive.
- Failed installation/upgrade must restore previous files and startup registration.

## Task 1: Core and protocol

Files: `windows/QuotaBar.Core/`, `windows/QuotaBar.Core.Tests/`.
Interfaces: records QuotaSnapshot/TokenUsage/AccountIdentity, QuotaDecoder, DetailInteractionState, RefreshState, PreferencesStore, RuntimeSession.

- [ ] Test fixtures, absent/invalid windows and Bank merging, token unavailable.
- [ ] Implement decoding and presentation semantics from QuotaCore.
- [ ] Test detail suppression, lock and persistent float close; refresh timing/errors.
- [ ] Implement pure state and atomic preferences with schema version.
- [ ] Test fake transport initialize/login/logout/stale response/timeout/restart.
- [ ] Implement stdio runtime session with bounded restart and cleanup.
- [ ] Run `dotnet run --project windows/QuotaBar.Core.Tests` and record evidence.

## Task 2: Windows UI

Files: `windows/QuotaBar.Windows/`.
Consumes Task1 state/events; produces application, tray, float, detail/settings and startup controls.

- [ ] Implement single-instance app and owned process lifetime.
- [ ] Implement tray tooltip mode, checked floating context option, refresh/settings/exit.
- [ ] Implement two-line floating quota, 4 DIP drag separation, screen recovery and hover close.
- [ ] Implement shared anchored detail, pure interaction state, lock/outside dismissal, resize/scroll, token chart/Bank/account.
- [ ] Implement system/light/dark theme, system/zh-CN/zh-TW/en language, login and startup settings.
- [ ] Cross-build `dotnet build windows/QuotaBar.Windows -p:EnableWindowsTargeting=true`.
- [ ] Windows device verification for native events, DPI and system lifecycle remains explicit.

## Task 3: Installation, build and validation

Files: `scripts/build-windows-standalone.ps1`, installer and packaging tests, Windows CI, current product docs.
Consumes UI binaries and runtime; produces self-contained candidate and checksums/provenance.

- [ ] Bundle official runtime and licenses; verify version and hashes, create Windows icon.
- [ ] Implement staged install/upgrade/rollback/uninstall with credential preservation and shortcut/startup handling.
- [ ] Test transaction failures and installed executable paths on Windows.
- [ ] Add Windows compile/core tests/packaging CI; local Core tests remain cross-platform.
- [ ] Update docs and roadmap with exact evidence and remaining device gates.
- [ ] Run governance and platform checks; do not claim release or device acceptance without evidence.
