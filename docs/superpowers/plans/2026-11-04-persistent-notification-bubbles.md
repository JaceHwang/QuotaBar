# Persistent Notification Bubbles Implementation Plan

> Implement in this session with regression tests before production changes.

**Goal:** Keep presented quota bubbles until the user chooses an action.
**Architecture:** Remove quota-change and outside-click dismissal, preserve active presentation while normal UI context temporarily prevents drawing, and retain explicit account/session cancellation and application shutdown safeguards. Apply equivalent behavior on macOS and Windows.
**Tech Stack:** Swift/AppKit and C#/WPF.
**Spec:** User request in this session, superseding the quota-change dismissal decision in the standalone progress roadmap.

## Constraints and review focus

- Closing the app or changing accounts must not expose a previous account's content.
- A hidden or locked screen must not show a bubble; restore it when the presentation context returns.
- Changing quota, clicking elsewhere, opening menus and normal UI navigation must not mark the active bubble read or drop it.
- Explicit notification settings that cancel a message must retain their existing authority.
- Test both actions, repeated environment transitions, long time intervals, and both quota periods.

## Tasks

- [x] Write macOS and Windows regression tests for changed quota and transient presentation suspension; observe failures.
- [x] Implement held active presentation and remove outside-click cancellation, keeping platform safety boundaries.
- [x] Run Swift and Windows Core tests, compile Windows UI tests, and verify the macOS candidate. Windows native UI and device validation remain outstanding.
- [x] Record verification, platform limits, and remaining work in the roadmap and project board.
