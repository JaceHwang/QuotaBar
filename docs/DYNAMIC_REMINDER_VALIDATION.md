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

Whole-branch review found two P2 integration cases: remove/re-add low levels between reads could replay, and a failed WPF delete could lock its reused editor. A single fix wave added immediate low-only configuration baselines (preserving depletion), both actual-controller regressions, and failed-delete recovery. Swift/.NET red failures were captured and full governance192Core+138AppKit passed after repair; native WPF is still pending. Scoped re-review, latest Windows/macOS CI and a clean signed Mac candidate plus actual local installation remain pending. No real phone test has been sent; no merge or public release is authorized. Product versions remain unchanged.
