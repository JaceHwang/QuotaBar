# QuotaBar macOS validation

Updated: 2026-10-12. Historical sections describe evidence at their release dates. Current-source acceptance is recorded separately.

## Published v0.5.0

Release tag commit: `fee843145fa6a5ab2b782a3e987eea66a1b76177`. [Public release](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.5.0).

- Exact-tag build: 345 tests in the then-current combined project passed.
- DMG, strict signatures, runtime/application digests and tagged source snapshots passed verification.
- Public assets were downloaded again and passed the complete release verifier.
- Installed 0.5.0 reads real quota. The user confirmed refresh with Codex closed, both menu bar lines complete, and vertical centering.
- Native login/settings, theme/language, clean Cmd-Q/SIGTERM shutdown, runtime crash recovery, single instance, startup toggle, installation/upgrade/rollback/uninstall and old-entry migration were tested on macOS 27.0 arm64.

Not verified: Developer ID notarization, complete minimum-OS/multiple-display/sleep/network/long-running device matrices. No Windows standalone implementation or device acceptance.

## Local standalone-only refactor (2026-10-11)

User authorized removal of local historical plugin files and the repository's legacy implementation. Active v0.5.0 and the isolated account directory were preserved. Current source is under `native/`, with `CodexQuota` and `QuotaCore` targets. Old host UI discovery, Accessibility scanning, floating indicator modes, Windows plugin and old installer implementations were removed.

The retained independent-app suite passed 142 tests. Legacy-only test cases were removed with their implementations, including 51 old installer tests; retained app-server, parser, account, state, detail/card, color and formatting assertions remain. Installer migration/transaction tests remain separately applicable. `./governance check all` passed, including 7 installer transaction tests and signing identity checks. The full native release build, copied resources, strict application/runtime signatures and DMG verification passed. The retained public v0.5.0 assets passed their SHA256 checks again. The installed app remained `ready`, `has_quota=true`, `host_ui=false`. Generated verification candidates and build caches were removed after validation. At the initial cleanup checkpoint this refactor had not yet been pushed or released; subsequent v0.5.1 publication is recorded below.

## Published v0.5.1

PR #26 and Release Please PR #27 passed all CI and were merged. Release tag commit: `2989a834eecc0bd888a73f49723b0ab57b0619c5`. Exact-tag 142 Swift tests, complete app/DMG build, resources, strict signatures, runtime/application digests and source snapshots passed. Five assets were published as latest. Installed v0.5.0 and account data were preserved; v0.5.1 device installation has not been performed.

Public v0.5.1 assets were downloaded again and passed the complete release verifier. GitHub latest API confirmed v0.5.1, draft=false, prerelease=false and all five assets.

## Current QuotaBar source (2026-10-12)

- Local full governance: 158 Swift tests and 10 installer/migration tests passed; signing selection, links, privacy, source isolation and shell syntax passed.
- Local candidates: full native release build, ICNS resources, transparent template-icon preview/alpha regression, strict signature, DMG and installed source snapshot matched.
- Device: real quota, default floating visibility, toggle persistence, drag position/restart recovery, click dismissal, entry switching, clean exit, rename to QuotaBar, Finder artwork/reopen, preserved login startup and menu bar display persistence passed on macOS 27.0 arm64.
- Context-menu floating action was code-reviewed but not clicked through computer automation; complete system-theme switching and multi-display unplug matrices were not device-tested.
- These are local-source observations, not evidence that published v0.5.1 contains these changes. New source CI, exact-tag packaging and public asset verification are pending for the next release.

Outstanding: Developer ID notarization, minimum-system/full multi-display/sleep/network/long-running matrices and Windows standalone.
