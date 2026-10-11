# Installation and Operations

> **Published platforms:** macOS v0.4.0 and Windows v0.4.1. See [current features](CURRENT_FEATURES.md) for the supported behavior and platform boundaries.


## Current release

macOS 14+ Apple Silicon users download the v0.4.0 arm64 DMG, checksum, and provenance files from
the [v0.4.0 GitHub Release](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.4.0).
Windows 11 AMD64/x64 uses the separately validated v0.4.1 setup described below. Every
installer asset is verified before publication.

## Windows 11 AMD64/x64

The formal v0.4.1 Windows x64 installer is published in the
[v0.4.1 GitHub Release](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.4.1).
It is the single installation entry point. It embeds the schema-v2 selector catalog and signed
compatibility-update configuration; do not edit `selectors.json` by hand. The generic selector and
signed compatibility updates recover automatically: an unavailable update keeps the packaged or
previously validated catalog usable. Setup waits briefly for local runtime health and reports whether
the indicator is visible, using the automatic safe dock, or needs compatibility validation.

Windows `v0.4.1` supports Windows 11 on AMD64/x64 only; Windows ARM64 is not supported. The current-user setup is unsigned (`NotSigned`)
and does not require administrator privileges.

There is no fixed Codex desktop file-version requirement. The overlay attaches only when the active
Codex title bar exposes the validated semantic UI Automation structure; unknown structures remain
hidden until a compatible selector is available.

### Download and verify

Download only `codex-usage-sidebar-v0.4.1-windows-x64-setup.exe` and
`WINDOWS-V041-SHA256SUMS.txt` from the
[v0.4.1 GitHub Release](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.4.1). Before launching the setup,
calculate its SHA-256:

```powershell
Get-FileHash .\codex-usage-sidebar-v0.4.1-windows-x64-setup.exe -Algorithm SHA256 | Select-Object -ExpandProperty Hash
```

Compare the digest case-insensitively with the matching checksum-file entry. A matching digest is
required before you run the setup. A mismatching SHA-256 means do not run it; delete the file and
download both files again from the release. Never disable Defender, SmartScreen, antivirus, or
system policy.

### Install, repair, and uninstall

Run the verified setup normally to install for the current user:

```powershell
Start-Process .\codex-usage-sidebar-v0.4.1-windows-x64-setup.exe
```

Because this public setup is unsigned, Windows may show **Unknown publisher**. Only after the
SHA-256 matches, select **More info** and then **Run anyway**. Do not use those controls when the
digest does not match.

The install root and automatic-start entry are:

```text
%LOCALAPPDATA%\CodexUsageSidebar\Current
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
```

Run the verified setup with `--repair` to repair the current-user installation, or with
`--uninstall` to remove it. Uninstall retains the installer-described local authorization/state
data, does not modify the official Codex installation, and does not require administrator
privileges.

Windows status output uses `runtime=unavailable` when no approved runtime is available,
`runtime=stopped` when the installed runtime is not running, and `runtime=running` when the
approved runtime is active.

### Agent-assisted automatic install

A coding agent may download the two release files, verify the SHA-256 above, and launch the setup
only when the digest matches. The agent must not bypass SmartScreen, Defender, antivirus, or system
policy. If installer, SmartScreen, uninstall, or Windows security UI appears, it must stop and get
immediate user confirmation before clicking. See [Install with an Agent](INSTALL_FOR_AGENTS.md) for
the deterministic prompt and evidence checklist.

### Validation boundary

The published `v0.4.1` Windows setup is bound to complete 130-case Windows 11 x64 real-device
evidence. Local install, repair, and uninstall results still describe only the operations actually
performed on the target machine. Unknown or unsupported UI Automation structures hide the overlay;
no coordinates are guessed.

## macOS 14+ Apple Silicon

### Requirements

- macOS 14 or later
- Apple Silicon Mac (`arm64`)
- Codex desktop app installed and running
- `codex` CLI with plugin support; no fixed Codex CLI version is required

Verify the CLI before installing:

```bash
codex --version
codex plugin --help
```

The installer does not compare the version printed by `codex --version`. It discovers `codex` in
the standard Homebrew/system locations and the current `PATH`, then relies on the command surface
advertised by `codex plugin --help`. A CLI that predates the plugin marketplace commands cannot
install this plugin until Codex adds that capability; this is a feature-capability check, not a
hard-coded version gate.

### Install with the graphical installer

Download the v0.4.0 arm64 DMG, its checksum file, and its provenance from the
[v0.4.0 GitHub Release](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.4.0):

```bash
shasum -a 256 codex-usage-sidebar-v0.4.0-macos-arm64.dmg
```

Compare the output with `MACOS-V040-SHA256SUMS.txt`. `MACOS-V040-PROVENANCE.json` records the
digest and exact source commit. Open the verified DMG, then open **Codex Usage Sidebar Installer**. The asset is not
notarized. If macOS blocks it, right-click the installer in Finder and choose Open. Click **Install**,
complete the isolated Codex login when prompted, enable Accessibility, then click **Verify**.

The installer embeds the verified v0.4.0 marketplace payload and places the companion and
LaunchAgent in the same locations used by the marketplace hook. It does not modify the Codex app.

### Resize the detail card

The small centered grip immediately above the footer is the macOS height control. Hovering it
shows an up/down resize cursor; dragging changes only the card height, preserves its fixed width and
titlebar anchor, and expands the scrollable row viewport. The card performs a full layout
reconciliation only when the drag ends, avoiding stutter while the pointer moves.

## Advanced: install from the marketplace

```bash
codex plugin marketplace add JaceHwang/codex-usage-sidebar
codex plugin add codex-usage-sidebar@codex-usage-sidebar
```

Start a **new Codex task**. Codex discovers plugin skills and runs `SessionStart` hooks at a task
boundary, as described by the [official Codex plugin workflow](https://developers.openai.com/learn/developers-codex-plugin/).
The hook installs the companion at:

```text
~/Library/Application Support/CodexUsageSidebar/Codex Usage Sidebar.app
```

and loads the user LaunchAgent at:

```text
~/Library/LaunchAgents/com.jace.codex-usage-sidebar.plist
```

## Authorize the isolated Codex home

The companion intentionally uses a separate `CodexHome`. It does not copy credentials from the
normal `~/.codex` directory. Authorize this home once with the official CLI:

```bash
plugin_home="$HOME/Library/Application Support/CodexUsageSidebar/CodexHome"
env CODEX_HOME="$plugin_home" codex login
env CODEX_HOME="$plugin_home" codex login status
```

This authorization survives companion restarts and normal Codex app upgrades.

## Grant Accessibility

Open `System Settings -> Privacy & Security -> Accessibility` and enable
**Codex Usage Sidebar**. macOS may require Touch ID or an administrator password.

Accessibility lets the companion identify native titlebar controls and static titles, then choose
a collision-free frame. It reads labels and frames only from eligible titlebar buttons/static text,
plus unlabeled structural group frames in the relevant region for pane-boundary detection. It does
not click, type, or read conversation content.

The release build uses a stable designated requirement to reduce permission churn. macOS remains
the authority and can request approval again after a security-policy or signing change.

Repair once after changing the switch:

```bash
"$HOME/Library/Application Support/CodexUsageSidebar/sidebar-control.sh" repair
```

## Verify

```bash
"$HOME/Library/Application Support/CodexUsageSidebar/sidebar-control.sh" status
```

A healthy adaptive-positioning result is read from the actual managed process and includes:

```text
pid=12345 version=0.4.0 runtime=shown placement=content-header anchor=labeledControl
language=simplifiedChinese language_source=process
indicator=654,1003,164,46 ... cached:false,source:labeledControl,edge:826
installed and loaded: .../Codex Usage Sidebar.app
```

`openLocation`, `labeledControl`, `rightPaneBoundary` and `fallback` identify semantic anchor
sources. Current release final geometry can differ after free-slot search or manual placement;
`x + width = edge - 8` is not a universal assertion. Check `mode`, `freeFallback` and the actual
rectangle in current runtime output; older releases may omit those fields. The badge and status
version must agree. See [Troubleshooting](TROUBLESHOOTING.md).

The language fields report the effective mapped UI language and how it was obtained. `process` is
the preferred steady-state result because it reflects the language Codex is actually displaying,
including the final result of the Auto setting. `preferences` and `system` are startup fallbacks.

## Update

For the graphical installer, download the newer DMG from that release's **Assets**, open it, and
click **Install** again. It replaces the managed payload atomically; repeat the guided login or
Accessibility steps only if the installer reports they need attention.

For a manual marketplace installation:

```bash
codex plugin marketplace upgrade codex-usage-sidebar
codex plugin add codex-usage-sidebar@codex-usage-sidebar
```

Start a new Codex task. The hook atomically replaces the old payload. Updating the official Codex
app does not normally require reinstalling this plugin.

During replacement, the installer compares a source-payload fingerprint and re-signs the copied
app with the stable local identity when available. This prevents a routine plugin reinstall from
silently changing the Accessibility identity of the already-authorized companion.

## Repair

Reopen the graphical installer and click **Install** to re-copy its embedded payload, then click
**Verify**. If the companion is already installed, the command below performs the same lifecycle
repair without downloading the DMG again:

```bash
"$HOME/Library/Application Support/CodexUsageSidebar/sidebar-control.sh" repair
```

Inside a new Codex task, the plugin skill can perform the same check:

```text
@codex-usage-sidebar check and repair the usage sidebar
```

## Uninstall

The graphical installer is only a launcher: ejecting its DMG does not remove the installed
companion. Use the managed companion's uninstall command:

Remove the companion first:

```bash
"$HOME/Library/Application Support/CodexUsageSidebar/sidebar-control.sh" uninstall
```

Then remove the plugin and marketplace:

```bash
codex plugin remove codex-usage-sidebar@codex-usage-sidebar
codex plugin marketplace remove codex-usage-sidebar
```

Uninstall removes only the companion's exact Application Support directory and user LaunchAgent.
It does not modify the official Codex app.

## Current controls and local testing

Right-click the indicator for Automatic,
Free or Locked; the footer gear provides the same modes plus Check for updates, Reload and Quit. The header
lock keeps the detail open and is independent from Locked position mode. Manual positions persist
per display. Crowding can switch Automatic to Free; choose Automatic explicitly to resume.

Build and install the working checkout only when you intend to test unpublished source:

```bash
bash plugins/codex-usage-sidebar/scripts/build-companion.sh
bash plugins/codex-usage-sidebar/scripts/sidebar-control.sh ensure \
  --plugin-root "$PWD/plugins/codex-usage-sidebar" \
  --plugin-data "$HOME/Library/Application Support/CodexUsageSidebar/Data"
"$HOME/Library/Application Support/CodexUsageSidebar/sidebar-control.sh" status
```

Run from the repository root. This updates the companion outside Codex and may preserve/reapply its
local signing identity. A local build is not a release or proof of clean-source provenance. Keep the
working-tree/snapshot distinction in [current features](CURRENT_FEATURES.md); the build script's
base commit alone does not describe uncommitted changes. Retain a backup before replacing a local
build that may contain different work.
