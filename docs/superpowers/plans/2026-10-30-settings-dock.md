# Settings Dock lifecycle plan

User approved the proposed behavior: keep existing settings UI, show Dock while settings are open or minimized, hide after settings close, reopen from Dock even if floating windows are visible. Keep menu-only startup, accounts, settings and message history unchanged. No new mockups or layout change.

- [x] Add native lifecycle regression; observe real activation-policy failures before implementation.
- [x] Promote only explicitly shown settings to regular activation. Use settings window identity/delegate to demote after close; preserve Dock during internal rebuilds; explicitly deminiaturize on reopening.
- [x] Verify opening/minimizing/restoring/closing/recreating and unrelated-window behavior; run existing AppKit/full governance, review and build an installable local candidate.
- [x] Install/test locally, update recovery records and existing draft without public release. Keep platform claims scoped to this Mac change.
