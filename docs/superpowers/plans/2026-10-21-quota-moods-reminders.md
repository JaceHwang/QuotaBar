# Quota Moods and Reminders Implementation Plan

> For agentic workers: execute inline with superpowers:executing-plans; use test-first steps and final independent branch review.

**Goal:** implement four opt-in experiences on macOS/Windows without services or runtime changes.
**Architecture:** independent pure experience engines, raw read observations, atomic receipt store, native notification routers and compact character drawing.
**Tech Stack:** Swift 6/AppKit, C#/.NET 10 WPF/NotifyIcon, shared JSON fixtures.
**Spec:** ../specs/2026-10-21-quota-moods-reminders-design.md

## Global Constraints

Four toggles default true (user amendment, 2026-10-21); missing settings/fields enable features, saved false values remain disabled. macOS checks permission for enabled reminder settings and requests only when undecided. Preserve30pt floating interaction,20pt icon and brand icons. Recovery confirmation15–120s; freshness120s; Bank72/24h. No redemption or public release. Use codex/feat/quota-moods-reminders; no product version edits.

## Review Focus

- Raw observations must never gain cached Bank data.
- Login cancellation and old queued callbacks must not revive prior account events.
- Window shape/plan changes and rounded0% cannot produce recovery/exhaustion.
- Notification routing must preserve software update policy.
- Character and sparkle views must not intercept pointer input or remain animating.

## Task 1: Contracts and persistence

- [x] Add failing Swift/C# contract tests for raw reads, Bank metadata and absent/null/value; run and observe missing behavior.
- [x] Add optional Bank id/resetType and raw-read event, maintaining display stream compatibility.
- [x] Implement versioned atomic store with epoch, bounded Bank receipts, corrupt-file suppression and write-failure handling; test temp directories.
- [x] Verify full protocol suites and commit feat: add quota experience observation contracts.

## Task 2: Experience engine

- [x] Write failing shared-sequence tests for baseline,20%/rounded0%,15/120s confirmation, ordinary drops, plan/length/epoch/sequence changes, notifications and stale values.
- [x] Implement observe(QuotaObservation, now) -> ExperienceUpdate and explicit baseline reset on enabled-mode changes.
- [x] Add Bank stage/group/id/expiry/corruption/restart cases; implement receipt-before-delivery behavior.
- [x] Run Swift and Core suites; commit feat: detect confirmed recovery and bank expiry.

## Task 3: Native notifications and settings

- [x] Add route/queue tests for update/recovery/bank/test, TTL, epoch cancellation and disabled toggles.
- [x] Implement one macOS delegate; Windows serial queue with shown/closed/clicked acknowledgement and bounded timeout.
- [x] Integrate four localized settings, permission handling and test actions; connect raw observations.
- [x] Run UI/protocol regression; commit feat: add opt-in quota experience reminders.

## Task 4: Mood and celebration

- [x] Add tests for independent toggles, visible-only celebration,2s expiry, drag/hide/logout cancellation and accessibility.
- [x] Draw approved rounded battery within20pt; local stars remain inside30pt floating area. Add reduced-motion support.
- [x] Render and inspect light/dark states; commit feat: add battery moods and recovery celebration.

## Task 5: Verification and candidate

- [x] Run governance check all and native Windows CI when authorized access permits; inspect actual PNGs.
- [x] Build macOS/Windows candidates with pinned official runtime and provenance; distinguish cross-build/native CI/device evidence.
- [x] Update README/privacy/troubleshooting/validation and roadmap/board after milestones; record unrun matrices.
- [x] Final independent review and test-first repair; no publish or merge.

## Commands

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path native
PATH=$HOME/.local/share/quotabar-dotnet:$PATH dotnet run --project windows/QuotaBar.Core.Tests
PATH=$HOME/.local/share/quotabar-dotnet:$PATH ./governance check all
Windows: dotnet run --project windows/QuotaBar.Windows.Tests --configuration Release
bash scripts/build-macos-standalone.sh
python3 scripts/build-windows-standalone.py

## Evidence

Implementation progress and actual verification live in docs/PROJECT_PROGRESS-standalone-app.md and .project-board via project_board.py; baseline/full-suite outputs in the plan workspace.


## Implementation status (2026-10-21)

Implementation tasks above completed in commits67a4dcb,15b98ba,03a6954,82bd495,f821129. Native CI39544046401 passed both platforms at f821129; local188 Swift tests, C# regressions and cross-builds passed; final macOS candidate signed/DMG/isolated startup verification passed. Independent P2 findings were reproduced and repaired. See validation record for actual commands and scope.

### Remaining manual acceptance (not certified by the completed automated tasks)

- [ ] Real system notification permission and click behavior on devices.
- [ ] Natural authenticated recovery and real Bank expiry delivery.
- [ ] Windows100/150/200%DPI, multi-screen and sleep/resume device matrix.
- [ ] Long-running CPU/memory comparison on both platforms.

No public release, merge or installation replacing the current user app.

## Approved B follow-up

The user selected concept B for the settings redesign on2026-10-21. Implement existing-flow changes inline: native sidebar and state legend;28pt mood, violet recovery, single recovery-or-celebration notification; context-menu dismissal; preference/identity synchronization; focused regression, full governance, native CI and candidate verification. Preserve all account/update actions and keep public release unauthorized.
