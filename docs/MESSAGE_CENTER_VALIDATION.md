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

## Final review and regression fixes

The fresh whole-feature reviewer found no Critical issue and one Important issue: macOS compact history could not reopen an already-selected row after returning to the list. A one-row native click/Enter regression first failed twice; explicit user activation now passes. The missing explicit category was promoted from a review minor because the approved detail design requires it. Five-category AppKit assertions first failed and now pass. Windows native category regression was observed failing at QuotaExhausted on d938468, CI40275031960/job121415856645, before adding the corresponding labels.

After the macOS fixes, all11 message UI tests and the full197Core/154AppKit suite passed, together with .NET and three Windows builds. Eight native macOS update-helper transaction scenarios passed. Windows native message UI had already passed on ac0c203; the new category regression and final packaging require the next native run.

The125/150/200% evidence is native RenderTargetBitmap output at those densities. It does not change the physical monitor DPI or exercise real scaling-dependent input/work-area behavior. Actual Windows display scaling and user-device interaction remain pending. This limitation does not reduce the native UI assertions or claim they were device tests.

## Verified candidate delivery

Product a9d4b6e: PR CI40275365757 passed both complete native jobs, including all message tests, standalone runtime startup/exit, concrete installation/upgrade/rollback/uninstall and update-helper scenarios. Windows category regression is green. The push run40275361935 failed after its receipt-failure scenario passed, during uninstall cleanup with AccessDenied on the managed app directory; this known timing problem is retained as failed evidence and is not claimed fixed. The same-source PR run passed all six Windows update scenarios.

- [Windows x64 candidate](https://github.com/JaceHwang/QuotaBar/actions/runs/40275365757/artifacts/12630810445): ZIP CRC, complete manifest, PE x64, official runtime digest,105 source hashes, setup payload and DLL hash verified. Provenance is clean PR merge482225332d727cbeb0e46670b2df4c001f99da32, whose feature parent is a9d4b6ee740e4257700ae0c8fef0a245d5181492; all source hashes match that product. ZIP SHA256: f0ea4363b03c3f1f5f0d6f0f23a124f812ddcfbb576dc0a337e732d20c529277. QuotaBar.dll SHA256:6c66a528e727eeaf909afc9083e9de8223ee1399e8a945709b8c59c7a7afef8f.
- [macOS arm64 CI candidate](https://github.com/JaceHwang/QuotaBar/actions/runs/40275365757/artifacts/12630615825): native CI startup, signatures, DMG and package verification passed. A separate clean local a9d4b6e candidate20261026-134046 passed135 source hashes, signed executable hash, isolated official-runtime startup/graceful exit and DMG verification; local DMG SHA256:afeac157ff626517b833dad5c9980b8f1b1c4347f7f4d4cc4411253f523db5cf.
- Authorized local Mac install completed transactionally with backups. Installed executable equals the local candidate; account and notification-policy fingerprints were unchanged. Actual menu/window showed Messages, unread/history and local-save status. A naturally produced real message opened by keyboard became read; after quitting/reopening, unread stayed zero and the original read record remained in history. No private message body or account data is included in this evidence.
- Six Windows language/appearance renders were inspected after the final label fix. Native bitmap density variants exist for125/150/200%; physical display scaling remains a device acceptance item.

## Requirement audit

| Requirement | Evidence |
| --- | --- |
| Messages entry in menus/settings, unread subset and all-message history | Both coordinators and settings views; native UI assertions; actual installed Mac menus/tabs |
| Auto-read only opened record; no successor read; preserve detail | AppKit and WPF selection/refresh regressions, one-row click/Enter reopen regression |
| All five real categories, channel merge, mobile/system-only and bubble pause | MessageCenterRoutingTests and Windows NotificationMatrixTests actual producer/router assertions |
| Tests/previews excluded, original snapshot preserved | Shared store fixtures and routing exclusion tests |
| Durable read/history, no age/count pruning,10,000 records | Dual MessageCenterTests, native virtualization tests, actual Mac restart |
| Stop/account epoch preserves history and uses current safe action | Router cancellation/restart/epoch tests, historical session UI assertions |
| Restore never replays notification work | Bound-store routing tests assert zero extra sends |
| Corrupt/future/locked history preserved; no false read success; retry merges pending | Dual store failure tests, AppKit failure/retry and native WPF corrupt/write-lock cases |
| C split detail, narrow back/reopen, long body, language/themes | Native tests and rendered artifacts, actual Mac window |
| Dual packaging and draft delivery | Complete native PR CI, verified candidates above, draft PR60; no merge/public release |

No important review finding remains after the verified regression fixes. Real Windows device/monitor scaling and natural phone receipt are explicitly outside the CI claims and remain user acceptance items.
