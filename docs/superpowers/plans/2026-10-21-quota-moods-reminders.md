# Quota Moods and Reminders Implementation Plan

> For agentic workers: execute inline with superpowers:executing-plans; use test-first steps and final independent branch review.

**Goal:** implement four opt-in experiences on macOS/Windows without services or runtime changes.
**Architecture:** independent pure experience engines, raw read observations, atomic receipt store, native notification routers and compact character drawing.
**Tech Stack:** Swift 6/AppKit, C#/.NET 10 WPF/NotifyIcon, shared JSON fixtures.
**Spec:** ../specs/2026-10-21-quota-moods-reminders-design.md

## Global Constraints

Four toggles default false. Preserve30pt floating interaction,20pt icon and brand icons. Recovery confirmation15–120s; freshness120s; Bank72/24h. No redemption or public release. Use codex/feat/quota-moods-reminders; no product version edits.

## Review Focus

- Raw observations must never gain cached Bank data.
- Login cancellation and old queued callbacks must not revive prior account events.
- Window shape/plan changes and rounded0% cannot produce recovery/exhaustion.
- Notification routing must preserve software update policy.
- Character and sparkle views must not intercept pointer input or remain animating.

## Task 1: Contracts and persistence

- [ ] Add failing Swift/C# contract tests for raw reads, Bank metadata and absent/null/value; run and observe missing behavior.
- [ ] Add optional Bank id/resetType and raw-read event, maintaining display stream compatibility.
- [ ] Implement versioned atomic store with epoch, bounded Bank receipts, corrupt-file suppression and write-failure handling; test temp directories.
- [ ] Verify full protocol suites and commit feat: add quota experience observation contracts.

## Task 2: Experience engine

- [ ] Write failing shared-sequence tests for baseline,20%/rounded0%,15/120s confirmation, ordinary drops, plan/length/epoch/sequence changes, notifications and stale values.
- [ ] Implement observe(QuotaObservation, now) -> ExperienceUpdate and explicit baseline reset on enabled-mode changes.
- [ ] Add Bank stage/group/id/expiry/corruption/restart cases; implement receipt-before-delivery behavior.
- [ ] Run Swift and Core suites; commit feat: detect confirmed recovery and bank expiry.

## Task 3: Native notifications and settings

- [ ] Add route/queue tests for update/recovery/bank/test, TTL, epoch cancellation and disabled toggles.
- [ ] Implement one macOS delegate; Windows serial queue with shown/closed/clicked acknowledgement and bounded timeout.
- [ ] Integrate four localized settings, permission handling and test actions; connect raw observations.
- [ ] Run UI/protocol regression; commit feat: add opt-in quota experience reminders.

## Task 4: Mood and celebration

- [ ] Add tests for independent toggles, visible-only celebration,2s expiry, drag/hide/logout cancellation and accessibility.
- [ ] Draw approved rounded battery within20pt; local stars remain inside30pt floating area. Add reduced-motion support.
- [ ] Render and inspect light/dark states; commit feat: add battery moods and recovery celebration.

## Task 5: Verification and candidate

- [ ] Run governance check all and native Windows CI when authorized access permits; inspect actual PNGs.
- [ ] Build macOS/Windows candidates with pinned official runtime and provenance; distinguish cross-build/native CI/device evidence.
- [ ] Update README/privacy/troubleshooting/validation and roadmap/board after milestones; record unrun matrices.
- [ ] Final independent review and test-first repair; no publish or merge.

## Commands

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path native
PATH=$HOME/.local/share/quotabar-dotnet:$PATH dotnet run --project windows/QuotaBar.Core.Tests
PATH=$HOME/.local/share/quotabar-dotnet:$PATH ./governance check all
Windows: dotnet run --project windows/QuotaBar.Windows.Tests --configuration Release
bash scripts/build-macos-standalone.sh
python3 scripts/build-windows-standalone.py

## Evidence

Implementation progress and actual verification live in docs/PROJECT_PROGRESS-standalone-app.md and .project-board via project_board.py; baseline/full-suite outputs in the plan workspace.
