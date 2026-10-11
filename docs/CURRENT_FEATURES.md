# Current feature inventory

Reviewed against `main` on 2026-09-22. The current public releases are macOS **v0.4.0** and
Windows **v0.4.1**. Release-specific packaging and validation details are recorded in the
[macOS](releases/macos-v0.4.0.md) and [Windows](releases/windows-v0.4.1.md) release notes.

## macOS controls

| Surface | Current behavior |
| --- | --- |
| Titlebar indicator | Two aligned rows for the 5-hour and 7-day windows when both are supplied; percentage, centered-dot separator and localized reset time. Width follows measured text, from 164 to 280 points. Missing secondary data retains a single-window presentation. |
| Hover | Opens the detail card only inside the visible indicator, excluding transparent window margins. Leaving the indicator/card dismisses a transient card. |
| Click | Pins/unpins the card. An outside click dismisses an ordinary pinned card. |
| Detail header lock | Keeps the detail card open across pointer departure and outside clicks until unlocked. This is separate from locking the indicator's position. Host visibility and stale-data rules still apply. |
| Indicator right-click | Opens the Automatic / Free / Locked position selector. The detail card is suppressed while this selector is open. |
| Settings gear | Position mode submenu, Check for updates, Reload companion, Quit companion. Check for updates opens GitHub Releases; it does not silently download/install a release. |
| GitHub footer icon | Opens the project repository. |
| Resize grip | Resizes only the scrolling details viewport. Width stays 360 points and the upper edge stays anchored, subject to screen bounds. Natural viewport is at least eight rows (256 points) and can grow with content; manual minimum is two rows (64 points). There is no separate product height cap; only available screen space limits the result. |

## Position modes

**Automatic** tries the semantic titlebar anchor with an 8-point gap, checks the final frame against
current obstacles, and searches available titlebar intervals using the actual indicator width.
The right-side default slot is also checked. If no safe slot exists, the indicator returns to its
default frame. If an interactive control overlaps that default frame (including the safety gap),
it switches to **Free**, captures the default position, and persists that mode. It does not hide
because of titlebar crowding and does not automatically switch back. Select Automatic explicitly
when you want automatic placement again.

**Free** permits deliberate left-button dragging. **Locked** uses the saved manual position but
prevents dragging. Positions are normalized per display, clamped to its visible area, and saved
with the active display identifier. Mode and manual coordinates survive restart. Switching from
Automatic to a manual mode captures the current position; collision fallback starts at the default
position rather than an older saved manual coordinate.

The scanner considers the complete toolbar region. Button roles and direct `AXPress`/`AXPick`
actions identify hit targets; generic `AXShowMenu`/`AXScrollToVisible` alone do not turn a container
or image into a button. Static title text remains an obstacle for free-slot selection. Compact
interactive controls that partially cross the titlebar band also contribute their bounds. This
avoids the former whole-titlebar-container collision. See [current design](CURRENT_DESIGN.md).

## Quota detail content

- Independent primary/secondary quota percentages and reset countdowns.
- A seven-column daily Token chart and total over the seven-day window, when data is available.
- Account display identity, bundle version, plan, period, Credits and Bank availability.
- Individual Bank credits, their status and expiry. Expiry accents are red at up to three days,
  orange above three through seven days, and green above seven days; unknown expiry has no urgency
  accent. These accents are separate from the remaining-quota colors.
- Remaining-quota percentage colors interpolate between the 10% red, 49% orange and 100% green
  anchors; the filled progress bar clips the corresponding gradient.
- Light/dark appearance, with an opaque pure-white detail surface in the light theme, and effective
  Codex language: Simplified Chinese, Traditional Chinese, English; unsupported languages use
  English. No independent language selector.

Locking the detail card is session interaction state, not the persisted position-mode setting.
The card's current visibility is not a guarantee of fresh data: snapshots dim after two minutes
and hide after five minutes. Missing snapshots, unavailable host windows, Settings pages and
background-host conditions can also hide the overlay. These visibility rules are distinct from
crowding fallback.

## Windows scope

Windows v0.4.1 includes WPF indicator/detail surfaces, Automatic/Free/Locked modes with
normalized display preferences, atomic JSON preference writes, detail pin/lock, outside-click
handling, indicator right-click position selection, settings controls (position/update/reload/quit),
quota/Token formatting, Bank expiry formatting, host-page policies and portable host tests. Its
light detail surface is opaque pure white. Windows viewport policy starts at eight rows, permits two
rows minimum and has no product height cap beyond the current display work area; it remains a
separate WPF implementation. The published download supports Windows 11 AMD64/x64 and carries its
own Windows build, packaging, provenance, and real-device evidence. Windows ARM64 is unsupported.
Unknown Windows host structures remain subject to the validated selector/compatibility policy and
fail hidden instead of using guessed coordinates.

## Installation, updates and provenance

The companion runs outside the official Codex app, under the user's Application Support directory.
A user LaunchAgent starts it. Control scripts fingerprint, copy, locally sign, verify and replace
its app payload. Authentication uses the separate `CodexHome` and official `codex login` flow.
Published downloads must retain their release-specific checksums and provenance.

The tracked payload records its source commit and executable digest in `assets/PROVENANCE.json`.
Official DMGs add exact release-tag provenance and checksums; uncommitted local builds are not release evidence.
Installation can re-sign the executable; byte hashes may differ while code with signatures removed
matches. Verify the installed signature and active process as well as the source payload hash.

## Code map

| Contract | Source |
| --- | --- |
| Quota display and Bank urgency | `native/Sources/SidebarCore/QuotaDetailFormatter.swift` |
| Placement decision and obstacle classification | `native/Sources/SidebarCore/ContentHeaderAnchorResolver.swift` |
| Mode persistence and drag coordinates | `native/Sources/SidebarCore/IndicatorPlacement.swift` |
| AX scanning and diagnostics | `native/Sources/CodexUsageSidebar/ContentHeaderLocator.swift` |
| Runtime mode transition | `native/Sources/CodexUsageSidebar/RuntimeCoordinator.swift` |
| Hover/pin/detail-lock state | `native/Sources/SidebarCore/QuotaDetailInteractionState.swift` |
| Detail geometry | `native/Sources/SidebarCore/QuotaDetailLayout.swift` |
| Settings and position menus | `native/Sources/CodexUsageSidebar/QuotaDetailSettingsMenuPopover.swift`, `IndicatorPositionModePopover.swift` |

Paths in this table are relative to `plugins/codex-usage-sidebar/`.
See [screenshots](images/current/README.md), [installation](INSTALL.md), [troubleshooting](TROUBLESHOOTING.md)
and [historical design index](superpowers/README.md).
