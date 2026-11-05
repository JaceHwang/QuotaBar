# Beta Experience Implementation Plan

> Execute task-by-task with regression tests and verification; preserve the existing uncommitted unified-message-list work.

**Goal:** Add an explicitly confirmed, opt-in beta update channel across macOS, Windows and GitHub publication.
**Architecture:** Keep schema 1 stable entries unchanged and add separately verified beta entries. Both clients persist channel consent independently, compare full restricted semantic versions, and enforce current consent through check, download and update handoff. Packages carry numeric OS-facing versions and a separately verified complete version identity.
**Tech Stack:** Swift/AppKit, C#/.NET/WPF, Python release/feed scripts, GitHub Actions, existing XCTest and .NET fixtures.
**Spec:** `docs/superpowers/specs/2026-11-05-beta-experience-design.md` (approved by user 2026-11-05).

## Global constraints

- Default disabled; two explicit confirmations before durable enable; no automatic installation or downgrade.
- The exact version format is `X.Y.Z` or `X.Y.Z-beta.N`; numeric components 0–65534, beta N 1–2147483647 without leading zero.
- Stable-only clients and existing schema 1 feeds keep working. Public beta assets are GitHub prereleases and never latest.
- Retain signature, provenance, digest, platform, update transaction, cancellation, user data, release tag and immutable asset checks.
- Existing message center modifications are user work and must remain intact. No public release without separate authorization.

## Review focus

- Channel changes during a check, notification, download or handoff cannot reinstate or install beta after successful opt-out.
- Corrupt consent data must fail closed without resetting other preferences; a failed write must not be reported as saved.
- Beta identity must survive OS numeric version fields and be verified across tag, provenance, executable metadata and transaction.
- Absent/invalid beta must not hide a valid stable update; invalid stable must not silently fall through to beta.
- Initial supporting stable updater must install beta and then beta-to-beta and beta-to-stable without changing user data.

## Tasks

### Task 1: Shared version, feed and consent behavior

**Files:** `native/Sources/QuotaCore/UpdateFeed.swift`, new core beta consent/version files, matching `native/Tests/QuotaCoreTests/`, `windows/QuotaBar.Core/UpdateFeed.cs`, new matching Windows core files and `windows/QuotaBar.Core.Tests/`.

- [ ] Add failing tests for stable/beta order, bounds, opt-out, selection of the newest permitted platform release, invalid/missing beta isolation and old schema compatibility; run tests to establish failure.
- [ ] Implement consistent restricted `ProductVersion` and feed selection; preserve existing OS numeric parsing. Re-run both native Core suites.
- [ ] Add failing tests for independent atomic consent store (absent, malformed, invalid type, save failure, restart and unrelated preferences untouched); implement and run on both Core suites.

### Task 2: Trusted downloads, identity and updater transaction

**Files:** `native/Sources/QuotaCore/TrustedUpdateRelease.swift`, `UpdateDownloadClient.swift`, `MacUpdatePackage.swift`, `ApplicationUpdateTransaction.swift`; corresponding `windows/QuotaBar.Core/` files; package build/verification scripts and both Core test suites.

- [ ] Reproduce rejection of valid beta and add tests requiring matching channel, exact tag and asset metadata, explicit beta consent, identity mismatches and cancellation/handoff race.
- [ ] Thread channel authorization through metadata, download and handoff; preserve all existing trust checks and default-deny beta. Implement numeric OS versions plus full version metadata, legacy-stable-only fallback and helper compatibility.
- [ ] Test beta.1 → beta.2 → same-number stable ordering, failure/rollback, mismatched metadata and no stale beta installation. Exercise platform-specific transaction fixtures where available.

### Task 3: macOS opt-in UI and controller

**Files:** `native/Sources/CodexQuota/QuotaUpdateController.swift`, `ApplicationUpdateService.swift`, `StandaloneCoordinator.swift`, new AppKit consent view if needed; `native/Tests/CodexQuotaTests/`.

- [ ] Add tests for two independent confirmations, cancellation, failed save, disabled default, persisted state, stale responses/reminders, cancellation at channel change, and selected B layout across languages/themes.
- [ ] Implement the B card and native confirmation flow; route update selection and installation through consent generations; display full channel identity and avoid automatic download. Run AppKit focused tests and inspect synthetic screenshots.

### Task 4: Windows opt-in UI and controller

**Files:** `windows/QuotaBar.Windows/SettingsWindow.cs`, `UpdateController.cs`, `ApplicationUpdateService.cs`, new WPF consent view if needed; `windows/QuotaBar.Windows.Tests/`.

- [ ] Add corresponding Windows native interaction, persistence, concurrency, keyboard/theme and channel-label tests.
- [ ] Implement same semantics as macOS with native controls and preserve existing settings. Run Windows Core tests and cross-compile; run native Windows UI tests only on Windows/CI and record actual evidence.

### Task 5: GitHub beta releases and feed generation

**Files:** `scripts/generate-update-feed.py`, `scripts/test-update-feed.py`, `.governance/project/build-release`, `.governance/release/beta.json`, `.github/workflows/prerelease.yml`, `.github/workflows/publish-platform.yml`, relevant package and verifier scripts.

- [ ] Add failing Python tests for channel/tag mismatch, stable isolation, platform skew, missing assets, invalid proof, beta order, immutable release assets and legacy feed compatibility.
- [ ] Generate verified stable and beta entries, support strict beta tags and full identities in staged packaging and release metadata; explicitly keep prerelease out of latest. No actual release or feed deployment.
- [ ] Run feed and release fixture tests; use simulated tags/assets for behavior that would otherwise publish; do not overwrite any published asset.

### Task 6: Integrated verification and handoff

**Files:** `docs/PROJECT_PROGRESS-standalone-app.md`, update operations and validation documentation, project board via utility.

- [ ] Run `./governance check all`, targeted AppKit render/interaction tests, Windows Core tests and builds. Document Windows native/CI/device verification separately.
- [ ] Build a local macOS candidate, verify provenance and smoke startup, then install only after tests pass and preserve current user data. Exercise the setting with isolated data where possible.
- [ ] Document actual results and unrun coverage, validate the project board, preserve previous work, and report any remaining limitations. Public release requires specific authorization.
