# macOS standalone v0.5.1

[Release](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.5.1). Source tag commit: `2989a834eecc0bd888a73f49723b0ab57b0619c5`.

The independent application and tests now live in `native/`; obsolete Codex host UI and Windows plugin implementations and historical packaging paths are removed. Quota/reset dates, details, isolated login and background refresh behavior are retained. Migration supports both executable names.

PR #26 and Release Please PR #27 passed CI. Exact-tag local build and verification passed: 142 Swift tests, resources, strict signatures, DMG, runtime/application digests and tagged source snapshots. Seven installer transaction tests also passed.

Apple Silicon, declared macOS 14+, bundled official Codex 0.144.1. Locally signed, not Developer ID notarized. v0.5.1 has not been installed on this device; prior v0.5.0 device acceptance remains recorded. Windows standalone and broader device matrices are pending.

All five public assets were downloaded and passed the complete release verifier. GitHub latest confirmed v0.5.1 as a non-draft, non-prerelease release.
