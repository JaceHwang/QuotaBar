# Windows settings and updater reliability

> **For agentic workers:** Use superpowers:executing-plans to implement the tasks inline.

**Goal:** Commit the device-tested local fixes into draft PR #64 without changing product versions or publishing.

**Architecture:** Preserve atomic settings writes and narrowly fall back for invalid-handle errors with backup/restore protection. Extract the helper readiness wait into Core so the 120-second bounded, cancellable wait can be tested with virtual elapsed time.

**Tech Stack:** C#/.NET 10, WPF, existing console regression suite.

## Tasks

- [x] Add failing settings persistence regressions: repeated transparency saves, unrelated fields, invalid handle only, interrupted write restoration, failed restoration and backup protection after retry/restart.
- [x] Implement preferences compatibility commit with backup protection; keep unrelated errors visible.
- [x] Add deterministic readiness regressions for a helper taking longer than 10 seconds, bounded timeout, early exit and cancellation; use a monotonic elapsed clock in production.
- [x] Extend the readiness limit to 120 seconds and wire the tested wait into the Windows updater; preserve hash verification and transactional rollback.
- [x] Run Core tests, Windows builds and available governance; review changes independently and document platform limits. Delivery: commit and update existing draft PR #64.

Validation: Core Release suite passed, Windows app/setup/native-test projects built with zero warnings/errors. Independent review found no important issues. Governance doctor and fast checks passed; full governance stopped at unavailable macOS `xcrun`. Windows native UI execution and a freshly built candidate device test remain for CI/handoff. The previously authorized draft push exception applies only to the local push hook, with repository checks and CI unchanged.

## Scope and evidence

Message history compatibility is already merged in PR #62. PR #64 already contains download progress and handoff improvements. Device logs captured a 10-second helper readiness timeout; extending only that deadline to 120 seconds allowed the user to finish updating. No account data, machine-specific diagnostic logs, patched assemblies or test version labels belong in Git. This device result does not establish the cause of the earlier generic rollback message.
