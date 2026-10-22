# Settings UI polish implementation plan

Spec: docs/superpowers/specs/2026-10-22-settings-ui-research.md. User approved implementation 2026-10-22. Execute inline in the existing isolated feature worktree; preserve uncommitted floating clipping changes. Product versions and public assets stay unchanged.

## Task 1: Native settings foundation
- Add failing native regressions for a bounded reading width, unique settings ownership and right aligned switch controls.
- Implement shared settings rows, grouped cards, system switches, consistent rounded actions, compact sidebar and constrained body width.
- Run Swift tests, inspect rendered artifacts; retain keyboard and accessibility labels.

## Task 2: macOS four pages
- Account: state aware primary actions, distinct identity/status, disclosure for runtime troubleshooting.
- Display: appearance and resident-entry groups, platform wording, controls at trailing edge.
- Experience: shared rows, five compact states below setting, single celebration preview and single test notification, permissions link; no duplicated account/display settings.
- Updates: version/status first, busy indicator and action, two system switches; conditional release actions remain.
- Extend and run native tests including all language/theme/page renders, short/large window, account and update states.

## Task 3: Windows parity
- Adapt WPF shared settings rows, aligned accessible toggles, button hierarchy, compact width and sidebar icons.
- Apply the same four-page organization and state visibility, without macOS-specific chrome.
- Extend Windows native tests; run Core and cross-build locally. Native tests/visual validation require Windows CI; record pending evidence accurately.

## Task 4: validation and local delivery
- Run full governance, independent whole-change review, address material findings.
- Build signed local macOS candidate, verify packaged lifecycle and install transactionally preserving account/settings/startup.
- Synchronize roadmap/board with exact local/CI/device status. Do not publish or merge without new authorization.

Review focus: hidden vs inactive action lifecycle; stale control references after rebuilding; live theme/language/preferences synchronization; offscreen controls, constraint conflicts, wrapping and scroll reachability; preview semantics, notification denial; queued update actions and checking state. No settings change may reset event baselines or lose persisted opt-outs.

## Outcome (2026-10-22)

Tasks1–4 implemented and verified. Source1cc9971 CI39721503294 and governance39721503231 passed; local207 Swift tests and WindowsCore14/14 plus native cross-build passed. Windows accessibility persistence test failed atda0a99e before the Checked/Unchecked fix and passed at2dc2319 and1cc9971. Independent review important findings closed. Final Mac candidate2dc2319 installed; its84-file native snapshot matches current source. Draft PR46 retained; no merge/public release. Details and explicit unrun device matrices: docs/validation/2026-10-22-settings-ui-polish.md.
