# Account Quota Overview Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task.

**Goal:** Implement the approved A account overview on macOS and Windows using existing quota detail data.

**Architecture:** Extend the macOS detail content with structured groups while preserving existing flat rows. Add dedicated native account quota views and update them through the existing coordinator rendering flow. Share Windows Token and Bank rendering with the existing detail window.

**Tech Stack:** Swift/AppKit, C#/WPF, existing QuotaCore and QuotaBar.Core formatting and models.

**Spec:** ../specs/2026-11-06-account-quota-overview-design.md

## Global Constraints

Use the approved A concept, all existing account actions and three languages. Account content width is at most960pt, other pages remain640pt. At content width below760pt stack Token/Bank. Preserve missing-data, stale-data and logout behavior. Product version changes follow Release Please only.

## Review Focus

- Unknown Token values must not become zero totals.
- Bank lists of arbitrary length remain reachable.
- Offline snapshots are distinguishable from fresh values.
- Account changes clear old values without requiring the floating panel to open.
- Minimum window and translated reset text do not clip or overlap.

### Task 1 — macOS grouped detail data and overview

Files: QuotaDetailFormatter.swift, new AccountQuotaOverviewView.swift, StandaloneCoordinator.swift, QuotaSettingsShellView.swift, AccountQuotaOverviewTests.swift.

- [x] Add focused regression for grouped resets/Bank data and responsive overview states, verify missing behavior.
- [x] Extend QuotaDetailContent with defaulted grouping fields while retaining original rows.
- [x] Implement semantic theme cards and integrate updates into normal settings rendering.
- [x] Run focused tests and export theme/language screenshots.

### Task 2 — Windows account overview with common detail rendering

Files: new AccountQuotaOverview.cs, SettingsWindow.cs, DetailWindow.cs, new AccountQuotaOverviewNativeTests.cs and Program.cs.

- [x] Add native coverage for primary/secondary, missing Token, Bank lists and narrow widths.
- [x] Reuse TokenBand and a common BankDetails factory between detail window and account page.
- [x] Integrate updates and authentication gating in SettingsWindow.UpdateStatus.
- [x] Compile locally and run Windows native CI when delivering.

### Task 3 — validation and local installation

- [x] Review complete diff and run governance check all.
- [x] Verify screenshots against A, including empty/offline states and minimum window.
- [x] Build/install a macOS candidate in /Applications and inspect the real account page.
- [ ] Update roadmap and board with exact verification evidence and remaining platform limits.
