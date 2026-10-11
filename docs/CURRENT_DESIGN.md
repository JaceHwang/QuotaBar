# Current design contract

Status: reviewed against `main` on 2026-09-22. Published versions are macOS v0.4.0 and Windows
v0.4.1. This document describes the shared behavior contract; platform-specific implementation and
release evidence remain separate.
[governance](GOVERNANCE.md) still controls release authorization. Historical specifications and
validation reports retain their original version scope. [Feature inventory](CURRENT_FEATURES.md).

## Placement pipeline

1. Discover the active Codex window and match Quartz/AX window geometry.
2. Traverse relevant toolbar branches, bounded to 1,000 elements per pass and depth 32. Scan starts
   at the window's left edge; the normal full-width scan does not need expansion passes.
3. Separate semantic anchors, structural pane geometry, static title barriers and actionable controls.
   Only button-role elements or direct press/pick actions establish interactivity. Auxiliary menu
   and scroll-to-visible actions do not make an entire container a hit target. Never infer occupancy
   merely because an AX element exposes some action.
4. Resolve Open Location, another eligible labeled control, a pane boundary, or a fallback anchor.
   Short-lived anchor retention (0.75 seconds) is a hint, not permission to reuse unvalidated space.
5. Validate the preferred indicator frame using measured width (164–280 points), the scanned region,
   8-point horizontal safety gaps, and toolbar-intersecting obstacle bounds. Check default and
   free-interval endpoints; do not enter an unscanned region.
6. If no collision-free frame fits, use the default frame. Only an interactive obstacle overlapping
   that frame triggers the persisted Automatic → Free transition. Capture the default frame in
   normalized display coordinates. Crowding never triggers hide; manual modes are not overridden.

The default frame ends 176 points before the window's right edge before window-bound clamping.
It is a preferred fallback, **not a guaranteed reserved region**. A semantic anchor's reported `edge`
can differ from the final display position after free-slot search or manual placement. Do not use
`indicator.maxX == edge - 8` as a universal health assertion.

The 0.1-second layout tracker and normal data-driven render path both apply the same decision.
The persisted mode is updated without recursively starting a second reconciliation. Right-click
and settings mode selection remain explicit ways to return to Automatic. The supported persistence
boundary is per-display manual position and selected mode, not detail-card hover/pin/lock state.

## Detail state and layout

The visibility state combines hover, click pin and explicit detail lock. Outside interaction clears
ordinary pin/hover state but preserves the detail lock. Showing the position selector suppresses
the detail card. Global/local mouse-down observers exist only to dismiss outside interactions;
they do not synthesize input or record click history.

The card has a 360-point fixed width, header (single or dual quota), optional seven-day Token band,
scrolling information rows and a footer. Its light-theme surface is opaque pure white. Natural row
viewport is at least 256 points, including sparse content; it can grow with more rows; minimum is 64.
Manual resizing preserves the top edge and is limited only by available screen space, with no
separate product maximum. Footer controls open the repository or a four-item settings menu. Settings position
submenu supports pointer transfer without premature dismissal. Check for updates opens Releases.

The Windows WPF surface follows the same pure-white light surface and screen-bounded height policy.
Right-clicking its indicator opens the same three placement choices used by the settings submenu.
Windows continues to use its own validated UIA and Safe Dock compatibility path; unknown host
structures remain hidden rather than being placed by coordinate guesses.

Bank expiry colors use remaining time, independent of remaining-quota color. Three-day and seven-day
thresholds are inclusive at the lower urgency boundary described in CURRENT_FEATURES.md. Unknown
expiry remains unaccented; used/expired status text continues to be shown.

## Diagnostics and privacy

Managed status includes active PID, version, visibility, mode, indicator bounds, semantic anchor,
scan counts, obstacle count, `freeFallback`, language and timestamp. `freeFallback` is the current
scan decision even in a persisted manual mode; it is not a history of transitions. Optional
`CUS_DIAGNOSTIC_OBSTACLES=1` adds role/action/frame metadata, without control label text.

Keep diagnostic sampling bounded, exclude conversation bodies and preserve the OS accessibility
permission boundary. Broad AX action support must be regression-tested against a full-width
`AXGroup` carrying only `AXShowMenu` and `AXScrollToVisible`.

## Verification and delivery boundaries

- Geometry tests cover fallback collision, cached-anchor revalidation, no-space handling, actual
  width, partial-band controls, unscanned areas and mode persistence.
- Captured structural fixtures cover the 1920×46 titlebar-container false positive and retain real
  `AXButton`, `AXPopUpButton` and actionable `AXCheckBox` obstacles.
- AppKit fixtures exercise current card/menu rendering across English, Simplified/Traditional
  Chinese and light/dark themes. Their demonstration data is not a live quota/account capture.
- Local runtime diagnostics confirmed Automatic mode with `freeFallback=false` after the fix.
  This is runtime evidence, not a screenshot or a complete release-device acceptance report.
- Windows source has separate implementation and validation requirements. Do not claim cross-platform
  visual/runtime parity or a new release from macOS-only checks.

Release Please, exact-tag packaging, immutable checksums/provenance, CI and platform acceptance
are required for publication. The catalog and release adapters use the governed `v0.4.0` tag;
macOS publication leaves the previously published Windows release unchanged.
