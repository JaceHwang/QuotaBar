# Changelog

## [0.4.1](https://github.com/JaceHwang/codex-usage-sidebar/compare/v0.4.0...v0.4.1) (2026-09-22)


### Bug Fixes

* **release:** decouple platform versions ([#19](https://github.com/JaceHwang/codex-usage-sidebar/issues/19)) ([6e99396](https://github.com/JaceHwang/codex-usage-sidebar/commit/6e9939633d4120ec74d89e716063cf503c9a9460))
* **sidebar:** align detail behavior across platforms ([b20ceb6](https://github.com/JaceHwang/codex-usage-sidebar/commit/b20ceb63d1db9c7f3e7591d10cf749429f6517a8))
* **windows:** refresh automatic overlay placement ([#16](https://github.com/JaceHwang/codex-usage-sidebar/issues/16)) ([1a15da3](https://github.com/JaceHwang/codex-usage-sidebar/commit/1a15da359ac76f35375870b5739473054c73d381))

## [0.4.0](https://github.com/JaceHwang/codex-usage-sidebar/compare/v0.3.5...v0.4.0) (2026-09-16)


### Features

* **macos:** add quota controls and verified staged publishing ([a5a3b93](https://github.com/JaceHwang/codex-usage-sidebar/commit/a5a3b93b95946eab0d333a96e52315a6c56531a0))

### macOS release details

- Automatic / Free / Locked indicator modes with per-display persistence and safe default-to-Free fallback.
- Detail lock, footer settings and Bank expiry urgency colors.
- Final-frame collision checks exclude auxiliary-only accessibility containers; hover and click use the visible indicator bounds.
- Native resource packaging supports Xcode 27; published executables retain macOS SDK 26.5.
- Bilingual README and current design/operations documentation include a real installed companion screenshot and clearly labelled native fixture galleries.
- macOS arm64 DMG, checksums and exact-tag provenance published; Windows remains at v0.3.3.

## v0.3.3 - 2026-08-23

- Published the macOS 14+ Apple Silicon DMG, SHA-256, and provenance assets alongside the existing
  Windows release assets.
- Added the macOS dual 5-hour/7-day quota card, weekly Token-usage aggregation, localized reset
  emphasis, and smooth fixed-width detail-card resizing from the centered footer grip.
- Published the formal Windows 11 AMD64/x64 setup, checksum, provenance, and signed compatibility-pack assets.
- Added a P-256-verified HTTPS compatibility update path so selector changes can ship without manual user adaptation.
- Completed and recorded the 85-case Windows 11 x64 real-device validation matrix.
- Kept unknown or unsafe titlebar UI Automation structures fail-hidden while accepting compatible Codex builds without a fixed file-version allow list.
- Added post-release Windows installation, diagnostics, provenance, and compatibility documentation in English and Simplified Chinese.

## v0.3.2

- Published macOS 14+ Apple Silicon DMG and Windows 11 AMD64/x64 setup assets with SHA-256 and provenance files.
- Added Windows parity for Token usage, account identity, themed plugin icon, reset emphasis, GitHub footer, and safe localized fallback behavior; Windows intentionally omits the Tibo X row.
- Relaxed host recognition from a fixed Codex file-version allow list to validated semantic titlebar structure checks; unknown layouts remain fail-hidden.
- Added companion/provenance SHA-256 regression coverage and synchronized the promoted companion metadata used by CI.
- Documented the published asset workflow and the remaining Windows real-device validation boundary.

All notable changes to this project are documented here. The project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Fixed the Windows selector packaging path to emit a schema-v2 catalog instead of the legacy
  schema-v1 device-test document, and reject invalid selector catalogs before publication.
- Made the runtime fall back to its built-in safe selector catalog when a stale packaged catalog is
  encountered, and refreshed the Windows plugin cache metadata so the current hook is installed.

- Add current-cycle daily and total token usage to the native quota popover.
- Add a compact borderless GitHub project link to the footer with the official GitHub mark,
  theme-aware hover shadow, and direct navigation to the repository.
- Add Codex account identity to the footer and refresh the visual documentation for light and dark
  themes.

### Changed

- Remove the outer quota-card stroke while retaining the native shadow and internal separators.
- Keep the footer GitHub control compact, rounded, and visually quiet until hovered.

### Fixed

- Use the validated signed Windows compatibility cache during runtime composition, preserve the
  packaged selector catalog on cache failures, and report v0.3.3 control status labels.
- Wait no longer than ten seconds after Windows setup install/repair for local runtime health and
  show localized healthy, safe-dock, or validation-required outcomes.

## [0.3.1] - 2026-08-21

### Added

- Publish the current native quota card, themed quota icons, account footer, token-usage chart,
  reset countdown emphasis, and adaptive titlebar fallback as the v0.3.1 source payload.
- Refresh the English and Simplified Chinese README screenshots with the current light and dark
  theme rendering.

### Fixed

- Keep the quota control visible in the reserved right titlebar position while the middle tab
  continues shrinking and no reliable native anchor remains.

## [0.3.0] - 2026-08-13

### Added

- Add a Windows 11 x64 WPF overlay, localized installer UI, strict UI Automation selectors, and
  fail-hidden placement for unknown Codex structures.
- Add separate Windows x64 and macOS arm64 v0.3.0 release-candidate pipelines with provenance and
  real-device evidence gates.

### Changed

- Place the Windows indicator beside the active task's Open Location control and track window
  movement, resize, DPI, language, layout, and theme changes.
- Match macOS countdown typography, fixed quota spectrum, and compact version badge styling.

### Security

- Bind Windows payload files, the official Codex runtime, device evidence, source commit, and
  packaging commit before a setup candidate can become publishable.
- Keep Windows ARM64 out of scope and preserve all published macOS v0.2.3 assets unchanged.

## [0.2.3] - 2026-08-10

### Fixed

- Prevent the quota control from overlapping native titlebar controls while the right pane is
  dragged left through intermediate widths.
- Slide the quota control to the nearest complete free titlebar slot when its preferred Open
  Location frame is occupied.
- Move immediately to the existing safe right-side fallback when no complete local slot remains
  before a static title barrier.
- Let an intentional resolved fallback replace an obsolete cached Open Location anchor while still
  retaining the last valid placement during a transient incomplete accessibility scan.
- Ignore degenerate content elements clipped to a 1-point line at the top of a fullscreen Codex
  window, preventing them from masquerading as titlebar obstacles and forcing an overlapping
  fallback when the right pane is closed.
- Re-scan eligible titlebar geometry on every 0.1-second placement tick instead of bypassing
  collision detection while a semantic anchor cache is fresh.

### Changed

- Scan the full horizontal reach of the 164-point indicator and recognize both native buttons and
  meaningfully visible static title text as occupied geometry, while pruning everything below the
  46-point titlebar.
- Apply geometry eligibility before reading accessibility labels, and stop traversing degenerate
  clipped branches before they can consume the bounded scan.
- Add real screenshots of the nearest-free-slot and safe-right-fallback layouts to both READMEs.

## [0.2.2] - 2026-08-10

### Changed

- Emphasize the numeric portions of reset and Bank expiry intervals with larger semibold type and
  the live quota color while keeping units and parentheses smaller and muted.
- Use the same semantic typography and contrast behavior in Codex light and dark themes.
- Measure emphasized attributed values with the same fonts used for rendering so compact date rows
  retain their existing alignment and wrapping behavior.

## [0.2.1] - 2026-08-09

### Fixed

- Honor an explicit Codex language selected in General settings even when an older renderer
  process still advertises the previous locale.
- Read only the quoted `localeOverride` inside Codex's `[desktop]` configuration table and ignore
  unrelated, malformed, or empty values.
- Preserve Auto behavior by falling through to the effective renderer locale whenever Codex has
  no explicit language override.

## [0.2.0] - 2026-08-09

### Added

- Match Simplified Chinese, Traditional Chinese, and English to the locale Codex is actually
  displaying, including the final resolved language when Codex is set to Auto.
- Fall back from the running renderer locale to Codex preferences and then macOS preferred
  language during startup; unsupported languages safely display English.
- Keep the quota detail card open after a click and dismiss it on the next click while preserving
  the existing hover interaction.
- Report only the mapped language and source in sanitized managed-process diagnostics.

### Changed

- Refresh the effective language once per second and re-render an already visible or pinned card
  without waiting for new quota data or reinstalling the plugin.
- Localize every quota label, date, interval, plan, Bank status, and empty state consistently.

## [0.1.9] - 2026-08-09

### Added

- Show the synchronized companion version in a compact blue outlined badge beside the quota-card
  title.
- Render the filled progress bar as a clipped red-to-orange-to-green spectrum with exact 10%, 49%,
  and 100% palette anchors.
- Publish sanitized runtime state from the active LaunchAgent so status reports its PID, bundle
  version, visibility, anchor source, and indicator frame.

### Fixed

- Re-sign the copied companion with the stable local identity when available, preventing plugin
  reinstall from changing the Accessibility code identity and falling back to the wrong position.
- Compare payload fingerprints instead of signed executable bytes, so installer-side signing does
  not cause perpetual replacement.
- Keep the complete quota title, compact version badge, remaining percentage, and spacing aligned
  without truncation.

## [0.1.8] - 2026-08-09

### Fixed

- Build release artifacts on the macOS 26 ARM64 runner with Xcode and macOS SDK 26.5 so the
  installed titlebar control retains the same AppKit behavior as the verified local build.
- Reject release binaries compiled for another architecture or an older macOS SDK before they can
  be packaged and promoted.

## [0.1.7] - 2026-08-09

### Fixed

- Keep the titlebar quota control visible at a safe right-side fallback position while Codex's
  accessibility tree is unavailable or incomplete during startup.
- Continue scanning after fallback placement and automatically restore the exact 8-point Open
  Location gap as soon as the native control is resolved.

## [0.1.6] - 2026-08-09

### Fixed

- Keep the last valid Open Location accessibility element during transient incomplete scans so
  pane animations and layout refreshes cannot move the quota control back to a fallback position.
- Delay the initial quota control until Open Location is resolved instead of briefly rendering at
  the legacy window-relative fallback position after installation or restart.
- Report the actual first accessibility scan in diagnostics, making fallback regressions visible
  instead of replacing them with a second cached lookup.

## [0.1.5] - 2026-08-09

### Fixed

- Keep the quota control exactly 8 points before the native Open Location button whether Codex's
  right pane is open or closed.
- Periodically revalidate cached accessibility anchors so opening, closing, or resizing a pane is
  reflected automatically.
- Render the detail card with Codex-native semantic window and separator colors instead of a
  visual-effect material that appeared unchanged inside the transparent companion window.

### Changed

- Widen the detail card to 300 points so reset and Bank expiry dates remain on one line.
- Label every Bank row as `Bank N到期时间` and use compact relative intervals such as `3d10h`.

## [0.1.4] - 2026-08-09

### Changed

- Match the quota detail card more closely to Codex's native popover material, border, corner
  radius, and theme-aware background.
- Increase the compact quota label size and weight to match nearby native titlebar controls.
- Show live relative intervals after the next reset and every Bank expiry date.
- Wrap long detail values within the existing compact card width instead of truncating them.

## [0.1.3] - 2026-08-09

### Fixed

- Preserve the visible quota control when clicking it activates the external companion, preventing
  the control from briefly hiding before the foreground fallback shows it again.

## [0.1.2] - 2026-08-09

### Changed

- Anchor the single quota control directly to the native Open Location button with an exact
  8-point gap.
- Cache the resolved accessibility element and sample its current frame every 0.1 seconds so pane,
  resize, and window movement cannot change the gap.
- Remove the sidebar/footer presentation state stack, surface classifier, and global event monitors.
- Use a continuous green-to-orange-to-red scale for the compact percentage, hover percentage, and
  progress bar.
- Run the app-server with a dedicated `CodexHome` authorized through the official `codex login`
  flow instead of relying on the user's normal Codex home.
- Select a stable local signing identity when available and apply a deterministic ad-hoc designated
  requirement in CI to reduce Accessibility permission churn.
- Expand the pure Swift suite to 71 tests, including anchor resolution, window matching, runtime
  configuration, color interpolation, layout, transport, and signing behavior.

## [0.1.1] - 2026-08-02

### Fixed

- Keep the usage control permanently in the right titlebar on Codex main surfaces, whether the left
  sidebar is expanded or collapsed.
- Remove the fragile dependency on the expanded sidebar footer/profile anchor.
- Continue hiding the companion on Settings and other completed non-main surfaces.

## [0.1.0] - 2026-08-02

### Added

- Live remaining quota and reset time in the expanded Codex sidebar.
- Adaptive compact quota placement before the right-side titlebar controls when collapsed.
- Theme-aware native hover card with plan, period, Credits, and every Bank entry.
- Automatic hiding on Settings and other completed non-main surfaces.
- Real-time app-server notifications, refresh recovery, stale-data handling, and reset checks.
- External LaunchAgent installation, automatic repair, and one-command uninstall.
- English, Chinese, human, and agent-focused installation documentation.

[0.1.0]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.0
[0.1.1]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.1
[0.1.2]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.2
[0.1.3]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.3
[0.1.4]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.4
[0.1.5]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.5
[0.1.6]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.6
[0.1.7]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.7
[0.1.8]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.8
[0.1.9]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.1.9
[0.2.0]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.2.0
[0.2.1]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.2.1
[0.2.2]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.2.2
[0.2.3]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.2.3
[0.3.0]: https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.3.0
