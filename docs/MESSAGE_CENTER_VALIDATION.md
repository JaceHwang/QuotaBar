# Local message center validation

## Scope and behavior

Approved C list/detail design replaces the unread entry on both platforms with a local unread/history archive. Opening one detail saves that message as read, removes only that unread row and preserves the detail. Tabs and programmatic selection restoration do not read messages. History contains all real snapshots across restarts and login epochs; preview/test events are excluded and history never re-enters delivery queues. No retention truncation is applied.

## Implementation evidence

- Core commit 1a57778 adds matching schema1 UTC-millisecond stores, immutable first snapshots, merged channels, atomic persistence and durable read state. Shared fixture and tests cover duplicate/generation/epoch identity, restart, unknown/corrupt files, blocked writes, pending recovery and10,000 records.
- Router commit53fcb50 archives before channel presentation, including system/mobile-only and bubble-paused cases. Tests cover all five categories, all-off exclusion, cancellation/stop preservation, restore with zero additional sends and historical actions opening current pages.
- macOS UI commit ef1739b adds native virtualized table/detail, compact back navigation, errors/retry and long snapshot scrolling. Nine message tests and13 existing settings tests passed locally; six language/appearance render variants were inspected.
- Windows UI commit ac0c203 adds the corresponding native virtualized WPF window and runtime tests, including narrow navigation, keyboard reopening, failed read-state writes, recovery, long bodies,10,000 rows and125/150/200% rendering. Release cross-build passed without warnings; this alone is not native runtime proof.
- Full local governance passed197Core and152AppKit tests, installer/startup/signing fixtures, .NET core behavior and three Windows Release builds. Native macOS updater transactions are tracked separately.

## CI and delivery state

Initial CI40274454521 macOS failed while compiling the new test fixture: Xcode26.5 could not type-check its nested expression in time. The fixture is split into explicitly typed local values without changing assertions. Failed-run evidence is retained; final native CI, reviewer findings, candidate provenance and device boundaries will be recorded below before delivery.

Windows user-device acceptance and actual phone delivery remain separate from CI. No real phone test was sent. The PR remains draft; no merge or public release is authorized by this delivery.
