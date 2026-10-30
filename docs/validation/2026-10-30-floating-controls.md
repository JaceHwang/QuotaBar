# Floating controls validation

User approved existing native settings style and direct implementation. Both platforms add a background transparency slider with a percentage value in Display settings.0% is opaque,100% visually transparent; developer default20%. Background is pure white/light or black/dark. Only background alpha changes, preserving existing text/icon and unavailable-state dimming. Changes save live without replacing the focused slider. The macOS settings window now supports standard minimization.

## Regression and review

Swift and.NET missing-preference tests first failed; native Mac missing slider/minimize assertions failed before implementation. Focused AppKit floating/setting tests10/10 and full197Core+156AppKit/.NET/three Windows Release builds passed. Native settings render variants were generated; representative Chinese light/English dark pages on both platforms were inspected.

Windows drag regression on51df329, CI41020142953/job123945353199, reproduced release order `finished,position,finished`: releasing capture synchronously raised LostMouseCapture and rendered old saved coordinates before saving the new position. The unified finalizer now snapshots/saves physical coordinates, clears pointer state before release, and finishes exactly once. Native assertions cover release/refresh position retention, unexpected capture loss and ordinary click separation.

Fresh read-only review identified one Important issue: fully transparent layered-window pixels pass native input to underlying windows, as described by [Microsoft](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features#layered-windows). Regression2ec0d59, CI41021725043/job123950343002, passed WindowFromPoint but failed actual native mouse down on transparent padding. The fix adds a2/255 theme-colored backing only at the transparent endpoint; it survives existing dimming while staying visually negligible. The configured surface still reaches alpha zero. This deliberate tradeoff preserves input at the cost of a sub1% residual backing tint.

Product a347861 CI41022057506 passed both complete native jobs. Windows tests include real native mouse down/move/up at100% on blank padding in both themes under unavailable-state dimming, live settings persistence, all existing UI and runtime startup, concrete installation/upgrade/rollback/uninstall, and six native updater scenarios. No Important review finding remains after native RED→GREEN verification; no minors were deferred.

## Candidate and local installation

- [Windows x64 candidate](https://github.com/JaceHwang/QuotaBar/actions/runs/41022057506/artifacts/12961764415): complete CI source/payload/runtime verification and native execution passed.
- [macOS arm64 CI candidate](https://github.com/JaceHwang/QuotaBar/actions/runs/41022057506/artifacts/12962656048).
- Local clean a347861 candidate20261030-155334:136 source fingerprints, signature/executable checks, isolated official-runtime startup/graceful exit and DMG verification passed. First packaging attempt failed on raw.githubusercontent.com DNS while fetching LICENSE; source-unchanged retry passed without weakening checks.
- Authorized Mac transactional install completed. Installed executable matches the candidate; account, notification policy and message archive fingerprints are unchanged. Actual settings show the slider and standard minimize button; live65%/20% feedback was verified and20% restored. Readable quota remains available. Native minimize capability/enabled button is covered by AppKit assertions; animation/restoration is not claimed as separate device proof.

Actual Windows physical-machine mixed-DPI/multi-monitor behavior, screen-reader sessions, long-running/save-failure UI and live system-theme transitions remain separate acceptance items. Native controls, labels, ranges, persistence and static themes were tested; CI renders are not real monitor-scale tests. PR60 remains draft; no merge, public release or real phone test.
