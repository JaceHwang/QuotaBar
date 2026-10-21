# Quota experiences candidate acceptance

Date: 2026-10-21. Branch: codex/feat/quota-moods-reminders. No public release authorization.

## Automated evidence

- Local governance: Swift Core141 + AppKit46 tests passed, C# core/shared-contract/protocol/login/install tests passed, Windows application/setup/native-test cross-builds zero warnings/errors.
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
