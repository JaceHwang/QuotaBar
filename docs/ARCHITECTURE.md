# Standalone architecture

`native/Sources/CodexQuota` owns the AppKit menu bar item, detail panel, native settings, startup registration and application lifetime. `native/Sources/QuotaCore` owns protocol decoding, isolated app-server session, quota/token/account models, formatting and refresh state. Shared fixtures live in `contracts/`.

The app launches only its bundled official Codex runtime over stdio. Official browser login stores credentials in the isolated `CodexHome`. The existing `CodexUsageSidebar` data-directory name is retained for account compatibility; it does not imply a plugin or desktop-UI dependency.

No host window discovery, Accessibility authorization/scanning, title-bar positioning or desktop-theme reading remains. Menu bar text and the detail card use system or manually selected language and theme. Global mouse events dismiss the card; global keyboard monitoring is not installed.

`install-macos-standalone.py` stages verified bundles and journals changes before activation. It can disable an existing legacy entry during migration, but this repository contains no legacy plugin implementation and no restore-to-plugin action. The app and runtime are stopped as owned processes before replacement.

Builds include licenses, source snapshots and runtime/application digests. Release builds require a clean checkout at the exact Release Please tag. Public assets are verified against signatures, version, runtime and tagged source; uploaded assets are never overwritten.

Windows standalone remains planned, with its own native shell/runtime ownership and the same protocol fixtures. No Windows plugin code is retained in this tree.
