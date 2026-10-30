# Floating controls implementation plan

> **For agentic workers:** Use superpowers:executing-plans for inline implementation, with one fresh final review.

**Goal:** Native background transparency slider on both platforms, normal macOS settings minimization, and reliable Windows free dragging.
**Architecture:** Preserve AppKit/WPF, use a persisted integer transparency percentage applied only to an opaque white/black background brush. Keep text/icons and hit area independent. Fix capture release ordering at the drag source.
**Visual direction:** User explicitly chose existing settings style and direct implementation rather than mockups. Preserve native typography, blue controls, compact single slider/percentage row, keyboard accessibility, three languages and light/dark/system themes. No redesign.
**Defaults:** Developer choice20% transparency;0%=opaque,100%=transparent. Invalid values clamp0–100; nonfinite values use20. Live updates save immediately, including disabled floating state; no account/history changes.

## Task1: Persist and display native transparency
- [x] Write failing Swift preference/background and settings slider tests, .NET preference persistence tests; observe RED.
- [x] Implement FloatingQuotaPreferences.backgroundTransparency and Preferences.FloatingBackgroundTransparency. Add slider/value row in display settings; live repaint and persist without rebuilding focused slider.
- [x] Render pure white/light and black/dark, retain background on hover; system appearance follows actual appearance. Test0/20/100%, malformed preferences and restart.

## Task2: Window controls and Windows drag regression
- [x] Add native settings miniaturizable assertion; observe RED; enable normal minimize button.
- [x] Add native WPF release/capture regression with Coordinator-equivalent finish/render callback. Observe native CI RED before fixing.
- [x] Save final physical position before release can trigger LostMouseCapture, finish exactly once; unexpected capture loss also preserves dragged position; clicks/right-click/close unaffected.
- [x] Validate clamping, persistence, redraw after release and source capture handling.

## Task3: Verify and deliver
- [x] Focused native Swift tests, .NET behavior and crossbuild; full governance; native Windows CI for drag/slider.
- [x] Fresh final review and fixes; inspect native visual artifacts, keep Windows device claims separate.
- [x] Update roadmap and board with implementation/test evidence; retain draft/no public release. No version changes.
