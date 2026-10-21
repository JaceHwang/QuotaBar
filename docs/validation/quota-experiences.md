# Quota experiences candidate acceptance

Date: 2026-10-21. Branch: codex/feat/quota-moods-reminders. No public release authorization.

## Automated evidence

- Local governance: Swift Core142 + AppKit46 tests passed, C# core/shared-contract/protocol/login/install tests passed, Windows application/setup/native-test cross-builds zero warnings/errors.
- Initial missing-interface tests failed before core/UI implementation.
- Review regressions reproduced Bank inventory-count and missing recovery-metadata failures, then both implementations passed after fixes.
- Approved B concept is in the design document. Actual native AppKit mood PNGs were generated from the drawing code and inspected; dark-mode face contrast corrected before final verification.
- Test output/artifacts are local under .dist/experience-ui; these are component renderings with sanitized data, not account screenshots.

## Native/candidate evidence

- First macOS candidate67a4dcb built/signed and DMG verified after a transient license-download TLS failure recovered on retry. Superseded by review fixes; do not deliver as final.
- Exact final-head macOS candidate/startup and Windows native CI: pending; append actual results below.

## Device matrix still requiring explicit evidence

- Native system notification permission denied/granted and actual notification click routing.
- Natural account recovery (not the test-notification action), and real expiring Bank grants.
- Windows100/150/200% DPI, multi-monitor movement/unplug and sleep/resume.
- Both-platform long-running CPU/memory comparison and OS Focus settings.

Do not turn simulated recovery fixtures, component PNGs, cross-builds or existing-version acceptance into proof of these scenarios. Preview/test actions never consume reset credits.

## Additional evidence

Native CI39543546995 and39543627047 passed both platforms at82bd495, including Windows UI PNGs, complete package, owned runtime shutdown, and installation lifecycle. Windows dark/light mood and settings artifacts were visually inspected. Subsequent corrupt-state suppression regression passed locally; final-head CI remains separately tracked.

First local packaged-startup invocation verified app/runtime startup and owned exit but failed cleanup due to incorrectly hiding native concurrently with Swift tests. Source was restored intact; this invocation is not counted as a passing script. Final validation uses native/.build serially.

## Final implementation commit f821129

- Native CI39544046401 passed both macOS and Windows at f82112909440633d28ad3ea929863f592e1180e7; all eight PR checks passed (push/PR runs included). Windows native UI, complete package verification, actual owned runtime startup/exit and concrete setup/upgrade/rollback/uninstall gates passed.
- Local final candidate: `.dist/standalone-macos/candidate-20261021-122702/QuotaBar.app`, source f821129, clean build, local-development-candidate, version1.0.1, official runtime0.144.1. Complete app/DMG build and strict signing verified.
- `python3 scripts/test-macos-standalone-startup.py .dist/standalone-macos/candidate-20261021-122702/QuotaBar.app --build-root native/.build` passed serially, including cleanup/restoration. Temporary source-hide directories absent afterwards.
- Local final component render tests3/3 passed; regenerated dark-mode face contrast inspected. Windows native mood and settings PNGs inspected from successful CI.
- Notification sound: the app plays no additional audio. macOS requests no sound; Windows tray notification audio follows OS configuration. OS notification settings were not modified.
- Real notification delivery/click permissions, natural account/Bank events, DPI/multi-screen and long-running matrix remain pending as listed above. The candidate has not replaced the user's installed public version.

Draft review: [PR43](https://github.com/JaceHwang/QuotaBar/pull/43). No merge or public release.

## Default-on amendment (2026-10-21)

The user changed all four defaults to enabled. Saved opt-outs remain unchanged; missing configuration or individual fields now enable the corresponding feature. macOS checks notification authorization for enabled reminder settings and requests it only while undecided. The earlier f821129 candidates above retain the previous defaults and are superseded for this requirement.

- RED: Swift defaults/missing-field assertions and C# defaults assertion failed with the old implementation.
- GREEN: local full governance passed: Swift Core142 + AppKit47, Windows Core behavior/protocol/install checks and native UI cross-build. Covers missing/partial preference fields, saved all-off, settings opt-out across restart, default reminder permission request and saved reminder opt-out without a request.
- Native CI39548520391 at6b5786e passed both platforms, including Windows native UI, complete candidate payload, actual runtime startup/exit and setup/upgrade/rollback/uninstall. Updated macOS and Windows candidate artifacts are available in that run. Real notification/device matrix remains pending.

## Approved B interface amendment (2026-10-21)

User selected concept B for both native settings implementations. Source changes include sidebar navigation, inline five-state legend, visual reminder explanations,28pt floating mood, distinct violet recovery and celebration-linked notification. Preview uses sample notifications only. Context menus dismiss locked/pinned details and suppress stationary hover until pointer exit.

Local full governance passed. Swift144 Core +53 AppKit tests passed, including three-language/light-dark settings renderings,28pt non-overlap, distinct recovered raster, context-menu suppression, sidebar persistence and both reviewed synchronization regressions. C#13/13 behavior plus protocol/install regressions passed; Windows app/Setup/UI test cross-build passed. Static review identified duplicated macOS controls and stale account summary; both produced failing behavioral tests before fixes and scoped re-review found no residual issue. Windows native execution/PNG inspection remains pending CI; cross-compilation alone does not certify native UI behavior.

- Local macOS candidatea9cdb65 (`candidate-20261021-152834`) built clean, signed, DMG verified, isolated runtime startup/exit passed. Transactionally installed to~/Applications/QuotaBar.app; installed provenance/source and running executable path checked. Actual installed settings AX tree exposes sidebar, four enabled controls, five labeled states and general controls.
- Windows native job inCI39562148342 passed UI, package integrity, runtime startup/exit and installation lifecycle; B light/dark PNGs inspected. Rounded settings buttons and shorter-row polish follow as Windows-only source changes and require fresh CI.

- Final source312a84d: nativeCI39562702421 succeeded on macOS and Windows. Windows UI/candidate integrity/runtime/setup/upgrade/rollback/uninstall passed. Final Windows B dark/light artifacts downloaded; rounded controls and theme contrast inspected. macOS source is unchanged from the installeda9cdb65 candidate. Actual installed macOS sidebar navigation Display→Quota management was exercised and returned to quota management.
- VoiceOver spoken output, physical keyboard-only traversal, actual notification clicks/natural account events, Windows DPI/multi-monitor and long-running matrices are not certified by these checks and remain pending. No merge/public release.

- Final macOS error-status follow-up: a test notification failure after opening settings was reproduced as a hidden label, then corrected by updating status text and visibility together. Swift suite now144 Core +54 AppKit; updated local candidate/install evidence follows.

- Notification-status follow-up1920c64 local clean candidate `candidate-20261021-153943`:198 Swift tests passed, complete signing/DMG/isolated runtime startup-exit passed; transactionally installed and running from~/Applications/QuotaBar.app. NativeCI39563449006 passed both macOS and Windows, including final candidates, runtime lifecycle and Windows installation gates. Windows sources unchanged from passed312a84d.

## User device acceptance and release authorization (2026-10-21)

The user explicitly confirmed both macOS and Windows device testing passed and authorized version updates, documentation, push and public release. This is user-reported acceptance of the current candidate; it does not supply individual DPI/OS/VoiceOver/natural-event/long-running results. Earlier no-release statements above are historical and superseded by this authorization. Release Please versions, exact-tag assets, downloaded-payload verification and public feed checks remain required publication gates.
