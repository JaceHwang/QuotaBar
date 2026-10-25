# Inline custom threshold implementation plan

**Goal:** Tighten master label/switch spacing to 8pt, place low-quota title and threshold on one row, and accept a custom integer threshold from 1–99%.

**Direction:** Continue the user-approved A matrix and existing explicit mockup opt-out. The current request directly specifies the layout adjustment. Preserve themes, other rows, matrix selection, channel behavior and account data.

**Architecture:** Native compact horizontal rows; preset dropdown plus Custom item opening a validated native input dialog. Cancellation preserves settings. Extend both policy decoding and warning-engine validation to 1–99 without changing schema or preset defaults. Custom value is visible in the selected menu item.

**Tasks:**
- [x] Add red shared warning fixtures and policy round-trip/range regressions; add custom select/cancel and native row geometry tests.
- [x] Implement compact layout, custom dialog and 1–99 range on both platforms.
- [ ] Verify focused tests, full governance, native renders and Windows compilation. Build and install candidate serially after a clean commit; preserve settings.

**Evidence:** Shared custom 1/15/99 warnings and decode round trips failed before changes, then passed. Native layout assertions reproduced 44–49pt master gaps and 54pt threshold vertical separation; now verify 4–12pt gap and less than 2pt vertical offset in all three languages/themes. Custom selection, cancel and invalid-value tests pass. Windows repeated editing P2 fixed and independently re-reviewed; Windows UI execution awaits native CI.
