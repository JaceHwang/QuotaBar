# Dynamic reminder validation

Approved A: compact editable chips, merged Bank, low immediately before Bank, simple channel master names, and three independent column shortcuts.

## Local verification

- Full governance:192 QuotaCore tests and138 AppKit tests passed, plus install/cleanup/signing fixtures, .NET Core behavior/lifecycle suites and Windows app/setup/UI test cross-builds.
- Real controller/router tests: low20→10 produces exact threshold metadata; empty low list retains depletion; Bank12 uses its exact mapping while24 retains mobile-only mapping; removed thresholds reject late actual-router completion.
- AppKit11 settings tests cover15 cells, independent columns and disabled state, add/edit/remove/invalid/Escape/save failure, mixed Bank channels, focus continuity,32-value wrapping and three languages/themes. Six native renders under native/.dist/dynamic-threshold-render were inspected.
- Bank shared dynamic fixtures cover72→24→12, jumps, empty/invalid/normalization/cap,8760-hour retention, restart and complete-inventory baselines. Independent task review found no P1/P2.
- Low shared fixtures cover levels, skips, exact period IDs, restart and edits. Review found scalar restart+edit could repeat a consumed low warning; shared red/green regression corrected it and scoped review marked addressed.
- Policy review found clearing the last Bank hour could reuse stale legacy channel rules. Both languages reproduced the failure and now retain current channels across clear→save/reload→add, including preventing a stale mobile channel from returning; scoped review addressed.
- WPF task review found synchronous rebuild on blur could remove a newly focused editor. Controls now reuse unchanged peers, the add action, and treat a field/its delete button as one edit region. Native-window forward/backward focus and keyboard-delete regressions added; code re-reviewed addressed. Native execution remains pending Windows CI.

## Pending delivery checks

Whole-branch review found two P2 integration cases: remove/re-add low levels between reads could replay, and a failed WPF delete could lock its reused editor. A single fix wave added immediate low-only configuration baselines (preserving depletion), both actual-controller regressions, and failed-delete recovery. Swift/.NET red failures were captured and full governance192Core+138AppKit passed after repair; native WPF is still pending. Scoped re-review marked both original P2 items addressed, then identified removed pending-low levels being consumed despite no longer being configured. Both engines now prune pending baselines to configured levels; shared red/green cases cover remove-before-read→readd and duplicate-before-cap normalization. Final scoped review marked all findings addressed with no new P1/P2. Clean signed Mac candidate candidate-20261025-204450 (source f4488e0, dirty=false) passed isolated real startup/exit, fresh defaults and DMG verification, then transactionally installed. Installed executable SHA matches the candidate; ready/has_quota=true. Actual UI AX/screenshot verified five rows, three column actions and dynamic chips; turning bubble off disabled all five cells and its shortcut while retaining checks, and turning it back on restored them. Windows generic style checks incorrectly required every action to be 30px, including approved 24px compact controls; test-only f7256da now asserts both explicit geometries, retaining all other style checks. Full local governance passed again; native Windows UI smoke/rendering in CI 40194686867 passed, including dynamic/focus/save-failure and geometry cases. Remaining whole-job candidate/update validation is still running; no Windows physical-device acceptance is claimed. No real phone test has been sent; no merge or public release is authorized. Product versions remain unchanged.


## Add-input and column-toggle repair (3a9923f)

- Real NSWindow red regression reproduces blank draft disappearing after add: makeFirstResponder followed by NSTextField.selectText triggers empty end-editing. Deferred focus plus currentEditor.selectAll passes both low/Bank add cases.
- Column shortcut now toggles full→none, partial/none→full, preserving peers/masters/thresholds and handling every custom Bank mapping. Swift UI and .NET policy regressions plus native WPF repeat-click assertions added.
- Complete local governance:192 Core +140 AppKit and all .NET/installer/build checks passed; independent review no P1/P2. Native CI40196405902 still running.
- Clean candidate-20261025-210853 installed with matching SHA, ready/has_quota=true. Actual installed UI added15% and12h, retained them across page rebuild, and toggled bubble all→none→all without peer changes. Test values removed to restore original empty lists; no real test push sent.
