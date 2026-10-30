# QuotaBar privacy

Updated: 2026-10-26.

Official account services and bundled Codex app-server supply quota and identity. The official runtime manages credentials in `~/Library/Application Support/CodexUsageSidebar/CodexHome`; QuotaBar does not copy the desktop account or add analytics. Optional Bark mobile push sends selected reminder text to Bark/APNs only after user configuration and enablement, as described below.

Quota/account details are shown locally. UserDefaults retains theme/language, floating visibility and position, and menu bar quota/icon mode. Local diagnostics contain process/phase/display flags; they omit credentials and email. Position is used only to restore the floating panel.

No host-window scanning or Accessibility authorization is required. Mouse monitoring dismisses the app's own detail card; global keyboard monitoring is not installed. The application and bundled runtime are separate from the official Codex desktop app.

Rename, upgrades and rollback preserve the account and preferences. Uninstall retains credentials and recoverable app backups; sign out in settings first to clear authentication through the supported official runtime. Do not remove the whole compatibility data directory to troubleshoot a display issue.

Release provenance includes public source hashes and commit IDs, not account data. Remove emails, quota/account details and unrelated files from shared screenshots, issues and logs. Never commit authentication files, local preferences, device screenshots, build caches or runtime binaries.

## Quota moods and reminders

Four experience toggles default on, preserving saved opt-outs. macOS checks notification authorization when reminders are enabled and requests it only if undecided; an OS denial is respected. The local `experience-state.json` stores a random authentication epoch and hashed Bank reminder grouping keys/stages/expiry times; it contains no email, credentials, avatar or raw protocol responses. Recovery baselines remain in memory. Bank receipts are bounded to 2,048 groups, with expired and distant entries pruned. A corrupt file is preserved under a random `.corrupt` suffix; the first known Bank snapshot suppresses historical alerts. System notifications contain quota percentages or known expiry summaries, omit account identity, and may appear on the lock screen according to OS settings. Test/preview actions do not consume Bank credits or modify real event baselines. These local features add no remote service or telemetry; optional Bark delivery is described separately below.

When either quota recovery notifications or recovery celebrations is enabled, one confirmed recovery message may be shown. Celebration previews also send an explicitly labeled example notification and do not modify real event baselines or reminder receipts.

## Character reminder bubbles (development branch)

Notification presentation adds no server, AI call, browser-cookie scan, or conversation-log access. Live delivery queues remain bounded in memory and are separate from the local message archive. Existing Bank receipts and update policies retain their existing storage rules.

The message center stores real reminder titles/bodies, observed quota or Bank snapshots, category, configured channels, timestamps, read status and an opaque session identity in `message-center.json` under the existing per-user application data directory. It contains no email, access token, Bark Key or delivery callback. Multiple channels share one logical record; preview/test messages are excluded. History and read status survive restart and sign-out, are not synced, and are not automatically deleted by age or count. Opening a detail marks that record read only after saving succeeds. History is never replayed as a new notification; older sessions are labeled and their actions open the current quota or update page. Uninstall retains application data. Storage errors preserve the original file and label unsaved records as temporary. Do not share this file if its quota history is private.

Bubble mode does not need OS notification permission. System/both mode uses the existing OS delivery path, so the OS may retain delivered messages. In-app bubbles do not automatically inherit system Focus; use the app's pause control. Test previews do not modify actual recovery baselines, Bank receipts or update policies.

## Optional Bark mobile push (development candidate)

Automatic mobile push defaults off. After configuration and enablement, valid recovery, Bank expiry and update reminder titles/bodies, the Device Key, fixed QuotaBar group and ordinary active priority are sent as HTTPS JSON to the fixed official endpoint `https://api.day.app/push`, then handled by Bark/APNs. Text may contain observed quota percentages, known expiry times or update summaries. Account email/avatar, login credentials, raw protocol responses, logs and conversations are excluded. Explicit phone tests send sample content; local bubble/celebration previews do not automatically send to Bark. No QuotaBar server or analytics is added. This version does not configure Bark message encryption and does not claim end-to-end encryption.

The Key is stored only as a macOS Keychain generic password or Windows current-user Credential Manager generic credential, never in ordinary preferences, URLs, logs, fixtures or receipts; unavailable secure storage has no plaintext fallback. Input does not automatically reveal an existing key. The eye control explicitly displays the saved key locally, or reveals the current draft; page changes and window deactivation mask it and clear the visible copy. Viewing a saved key does not change delivery preferences, copy it into a draft, or transmit it. Non-sensitive configuration records enabled state, schema and a random generation. A separate versioned, atomic mobile receipt file retains only event identity/generation, timestamps and attempt/acceptance status, capped at 256 records with a 30-day retention policy that protects live identities. That receipt file stores no message body or request/response history; the separate local message center is described above. Corrupt files are preserved and current events are conservatively suppressed.

Mobile delivery is independent of desktop OS permission, widget visibility and bubble pause. It still needs a running, awake computer and network. Service acceptance is not phone-display confirmation. Failures and ambiguous timeouts are not automatically retried. Disable/clear/config changes cancel pending work, but already handed-off pushes cannot be reliably recalled. Bark/iOS controls notification retention, lock-screen display, Focus and sounds. See the [setup guide](BARK_MOBILE_PUSH.zh-CN.md).

If mobile receipts are corrupt, a durable recovery marker survives immediate restart and automatic mobile push is disabled conservatively. Explicit re-enabling snapshots current known reminders as suppressed before accepting new events; corrupt originals remain preserved. Expired unprotected receipts are pruned when reserving attempts or establishing a baseline.

## In-app update downloads (development candidate)

An explicit update click contacts the fixed public GitHub repository API and allowed GitHub asset hosts, exposing ordinary network metadata such as your IP address. Requests carry no app credentials, Bark Key, cookies or GitHub token. Private staging stores package hashes, source provenance, operation IDs and nonce receipts, never quota/account responses. Verification uses GitHub HTTPS release metadata, not a new independent publisher signature. See [update details](IN_APP_UPDATES.zh-CN.md).
