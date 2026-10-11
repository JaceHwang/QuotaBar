# macOS standalone validation

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

The retained independent-app suite passed 142 tests. Legacy-only test cases were removed with their implementations, including 51 old installer tests; retained app-server, parser, account, state, detail/card, color and formatting assertions remain. Installer migration/transaction tests remain separately applicable. `./governance check all` passed, including 7 installer transaction tests and signing identity checks. The full native release build, copied resources, strict application/runtime signatures and DMG verification passed. The retained public v0.5.0 assets passed their SHA256 checks again. The installed app remained `ready`, `has_quota=true`, `host_ui=false`. Generated verification candidates and build caches were removed after validation. This refactor is not pushed, CI-tested or released.
