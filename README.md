# QuotaBar

Independent macOS menu bar and floating quota app for Codex accounts. A bundled official Codex 0.144.1 runtime reads quota using an isolated account; Codex desktop and its plugin UI are not required.

[Latest release v0.6.0](https://github.com/JaceHwang/codex-usage-sidebar/releases/latest) · [Apple Silicon DMG](https://github.com/JaceHwang/codex-usage-sidebar/releases/download/v0.6.0/codex-quota-v0.6.0-macos-arm64.dmg) · [中文](README.zh-CN.md) · [Documentation](docs/README.md)

## Features

- Menu bar: remaining quota and reset dates on two centered lines, or an 18pt transparent monochrome icon. Settings → “Show quota information in menu bar” switches modes and remembers the choice.
- Floating button: enabled by default, freely draggable with a saved position. Right-click the menu bar item → “Show floating button” toggles it independently. The local development candidate adds a right-side close button on hover; closing persists the hidden state, and the menu bar option restores it.
- Details: hover the floating button to preview; click to pin, click again to dismiss unless locked. The lock button keeps details open. Outside clicks dismiss unlocked details.
- Native settings: official browser login, sign out, refresh, runtime reload, theme, simplified/traditional Chinese or English, and optional login startup.
- Rename-safe installation: upgrades from `Codex Quota.app` to `QuotaBar.app`, preserving the isolated account and preferences, with transaction recovery and rollback.

## Install and reopen

Download the DMG and all supporting files from the same release, then verify `CODEX-QUOTA-SHA256SUMS.txt`. The distribution filename remains `codex-quota-vX.Y.Z-macos-arm64.dmg`; the current app inside is `QuotaBar.app`.

Use the attached installer for upgrades and migration:

```bash
python3 install-macos-standalone.py install --candidate '/Volumes/QuotaBar/QuotaBar.app'
```

The installer uses **`~/Applications/QuotaBar.app`**, not `/Applications`. Finder's Applications sidebar usually opens `/Applications`; press **Command + Shift + G**, enter `~/Applications`, and double-click QuotaBar to reopen after quitting. Double-clicking an already running app opens settings. Closing settings keeps the app running; Quit or Command + Q stops it and its runtime.

Apple Silicon, declared macOS 14+, device-tested on macOS 27.0. Locally signed; **not Developer ID notarized**. First launch can require user approval in macOS Privacy & Security. The Windows 11 x64 candidate passes native CI, and the user reports device acceptance of the initial candidate. The latest candidate retains the Windows detail layout with fewer token statistic rows, revised time rows and an inline Tibo button; a single circular colored icon is shared by the tray and app in every theme; updated visuals await device confirmation. See [Windows candidate guide](docs/WINDOWS_STANDALONE.zh-CN.md). Quota percentages are account usage limits, not API cash balances.

## Development and verification

```bash
./governance doctor
./governance check all
CUS_RUNTIME_BINARY=/path/to/codex bash scripts/build-macos-standalone.sh
```

Requires Xcode and official `codex-cli 0.144.1` for packaging. Native source/tests are in `native/`; transaction installation, packaging and exact-tag provenance verification are in `scripts/`. Release Please owns product versions. Runtime binaries, credentials and private screenshots are not source artifacts.

Read [progress](docs/PROJECT_PROGRESS-standalone-app.md) before each development session and update the project board after milestones. See [architecture](docs/ARCHITECTURE.md), [privacy](docs/PRIVACY.md), [validation](docs/validation/macos-standalone.md), and [governance](docs/GOVERNANCE.md).

Published v0.6.0 includes QuotaBar branding and floating/menu bar controls. All five public assets passed complete download verification. Earlier v0.5.1 used the previous Codex Quota name. Historical code and immutable assets remain in Git history and earlier GitHub releases.
