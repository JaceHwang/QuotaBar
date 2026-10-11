# Architecture

This page describes the architecture shared by the published macOS **v0.4.0** and Windows
**v0.4.1** releases, with platform-specific UI and lifecycle components called out below.
[Current feature inventory](CURRENT_FEATURES.md) · [Current design contract](CURRENT_DESIGN.md)

## Components

1. Marketplace manifest, skill and SessionStart hook locate and ensure the companion.
2. The control script fingerprints, copies, signs, verifies and atomically replaces the user app;
   it manages the LaunchAgent without changing the official Codex application.
3. Swift/AppKit renders one quota indicator, a detail card and position/settings popovers.
4. SidebarCore implements quota decoding, formatting, language, freshness, layout, pointer state
   and persisted position models; InstallerCore handles the macOS installer contract.
5. Windows has a separate portable core, WPF host, UIA compatibility boundary and installer. Its
   release evidence and compatibility policy remain independent from the macOS AX implementation.

```text
plugins/codex-usage-sidebar/
├── contracts/                 # shared sanitized fixtures
├── native/Sources/
│   ├── SidebarCore/           # data, layout and interaction policies
│   ├── CodexUsageSidebar/     # AppKit, AX scanning and runtime coordinator
│   ├── InstallerCore/
│   └── CodexUsageSidebarInstaller/
└── windows/                   # portable Core + native WPF/UIA + installer/tests
```

## Data and presentation flow

```text
Codex discovery → isolated CodexHome → local app-server JSON-RPC/stdio
  → quota windows + account + Bank/Credits + seven-day Token data
  → formatter + effective language/theme
  → measured-width indicator and fixed-width detail card
```

Host discovery uses the active Codex bundle and its app-server executable. Notifications update
quota snapshots; bounded polling, reset checks and stalled-stream recovery maintain freshness.
Snapshots dim after two minutes and hide after five. Missing snapshots/windows, Settings and
background host states are separate visibility gates from placement crowding.

The effective renderer language, Codex preferences and macOS language fallback resolve Simplified
Chinese, Traditional Chinese or English. Unsupported locales use English. A one-second check can
refresh visible text without issuing a quota refresh. Raw process arguments are not logged.

## Placement and persistence

[Placement flow](images/placement.svg) is a schematic. The scanner samples the relevant complete
46-point titlebar band every 0.1 seconds, matching the correct AX window to Quartz geometry.
Compact controls partly crossing the band can be obstacles too. Bounds are checked before labels
are read; ordinary structural groups are used as pane geometry, not semantic text sources.

The code separates preferred semantic anchors from final collision checks. Button roles or direct
`AXPress`/`AXPick` actions identify actual interaction targets; auxiliary `AXShowMenu` and
`AXScrollToVisible` alone do not. Static titles participate in free-slot selection. The final
frame uses the measured 164–280-point width and 8-point gaps, revalidating even cached anchors.

Automatic mode searches safe space, then uses the default right-side frame. If that default collides
with an interactive control, it captures the default frame and persistently switches to Free.
It never hides solely because of crowding and never switches back without explicit selection.
Free permits dragging; Locked preserves the saved position without dragging. UserDefaults stores
normalized per-display coordinates, the active display and mode. The default slot is not guaranteed
empty. Anchor `edge` is not a universal final-frame coordinate.

## Detail interaction

Hover is transient; click pin is dismissed by an outside click; the header lock keeps the detail
card open until unlocked, subject to normal host/freshness visibility gates. The detail lock is
independent of Locked position mode and is not the persisted mode preference.

The 360-point card contains one/two quota bars, an optional seven-column Token band, scrolling rows
and a footer. Natural row viewport is at least eight 32-point rows; more content can grow the card
up to 720 points. Manual resizing has a two-row minimum and screen bounds take precedence. Footer
settings provide position mode, a Releases link, reload and quit; the GitHub icon opens the repo.
Local/global mouse-down monitors dismiss outside interactions while menus/pinned content are open.
They neither record a click history nor synthesize input.

## Runtime evidence

The managed process writes sanitized `runtime-state.txt`: PID, bundle version, visibility, mode,
geometry, semantic anchor, obstacle/scan counts, `freeFallback`, mapped language and timestamp.
Status accepts that file only if its PID matches the LaunchAgent; a separate diagnostic process
is not equivalent to a live overlay. Opt-in obstacle diagnostics add role/action/bounds metadata,
never labels. See [troubleshooting](TROUBLESHOOTING.md).

## Build and release boundary

The tracked payload records its source commit and executable digest. Official
release assets require exact-tag build provenance, checksums and platform verification according
to [governance](GOVERNANCE.md). A locally installed executable may be re-signed; verify signatures
and compare normalized executable code when investigating expected signing-only hash differences.

[Privacy](PRIVACY.md) documents persisted position settings and input-observer scope.
