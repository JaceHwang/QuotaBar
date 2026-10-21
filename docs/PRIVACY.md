# QuotaBar privacy

Updated: 2026-10-12.

Official account services and bundled Codex app-server supply quota and identity. The official runtime manages credentials in `~/Library/Application Support/CodexUsageSidebar/CodexHome`; QuotaBar does not copy the desktop account, upload quota/account data to an extra service or add analytics.

Quota/account details are shown locally. UserDefaults retains theme/language, floating visibility and position, and menu bar quota/icon mode. Local diagnostics contain process/phase/display flags; they omit credentials and email. Position is used only to restore the floating panel.

No host-window scanning or Accessibility authorization is required. Mouse monitoring dismisses the app's own detail card; global keyboard monitoring is not installed. The application and bundled runtime are separate from the official Codex desktop app.

Rename, upgrades and rollback preserve the account and preferences. Uninstall retains credentials and recoverable app backups; sign out in settings first to clear authentication through the supported official runtime. Do not remove the whole compatibility data directory to troubleshoot a display issue.

Release provenance includes public source hashes and commit IDs, not account data. Remove emails, quota/account details and unrelated files from shared screenshots, issues and logs. Never commit authentication files, local preferences, device screenshots, build caches or runtime binaries.

## Optional quota experiences (development branch)

Four experience toggles default off. The local `experience-state.json` stores a random authentication epoch and hashed Bank reminder grouping keys/stages/expiry times; it contains no email, credentials, avatar or raw protocol responses. Recovery baselines remain in memory. Bank receipts are bounded to 2,048 groups, with expired and distant entries pruned. A corrupt file is preserved under a random `.corrupt` suffix; the first known Bank snapshot suppresses historical alerts. System notifications contain quota percentages or known expiry summaries, omit account identity, and may appear on the lock screen according to OS settings. Test/preview actions do not consume Bank credits or modify real event baselines. No remote service or telemetry is added.
