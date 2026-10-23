# QuotaBar architecture

Updated: 2026-10-12.

`native/Sources/CodexQuota` owns the AppKit menu bar, floating button, shared detail panel, settings, startup registration and application lifetime. `native/Sources/QuotaCore` owns JSON-RPC, the isolated app-server session, quota/token/account decoding, refresh state, formatting and pure detail interaction state. Shared protocol fixtures are in `contracts/`.

The app launches only bundled official Codex 0.144.1 over stdio. Official browser login keeps credentials in isolated `CodexHome`; no desktop credentials are copied. The `CodexUsageSidebar` data-directory and `com.jace.codex-quota` bundle ID stay stable across the QuotaBar rename.

## UI and state

- `StandaloneCoordinator`: runtime ownership, refresh, menu actions, native settings and lifecycle.
- `FloatingQuotaButton`: nonactivating 30pt panel, original quota typography/icon, click/drag separation, saved position and visible-screen recovery.
- `QuotaDetailInteractionState`: hover, click pinning, hover suppression and independent lock semantics. Switching from menu bar to floating details clears the other entry's display state; unlocking restarts pointer tracking.
- `StatusItemDisplay`: persisted quota/icon choice. Quota uses the centered two-line template image; icon uses an 18pt transparent vector template tinted by macOS.
- `QuotaDetailPanel`: shared native details; the active entry determines its anchor. Locking does not prevent the app from exiting.

The menu bar context menu owns the checked floating visibility option. Settings owns menu bar quota/icon mode. Their defaults are enabled and their preference keys are independent. Position recovery handles negative work-area coordinates and removed screens without host-window discovery.

No Accessibility authorization/scanning, host title-bar positioning or desktop-app theme reading is used. Mouse monitoring handles card dismissal; no global keyboard monitor is installed. Closing settings leaves the app running; Quit stops the owned runtime and hides panels.

## Installation and release

The transaction installer targets `~/Applications/QuotaBar.app`, detects previous `Codex Quota.app`, stages verified bundles and records original paths before activation. Failure recovery restores the previous path and login startup; subsequent rollback/uninstall re-resolves the active path. Account data and preferences are preserved.

Builds contain AppIcon.icns, runtime licenses, provenance and source snapshots. Releases require a clean checkout at the exact Release Please tag, then verify signatures, version, runtime/application digests and tagged sources. Uploaded assets are immutable. Windows implementation is in `windows/`: a UI-independent .NET 10 Core, WPF/NotifyIcon application, and per-user Setup transaction adapter. Tray quota appears in its tooltip according to the approved platform choice. Windows v0.7.0 is published after native startup/exit and installation lifecycle CI, user-reported complete Windows 11 acceptance, and public ZIP/provenance/source verification. Windows release jobs build only from a clean exact Release Please tag and never overwrite assets; macOS remains at v0.6.0.

## Bark mobile delivery (development candidate)

Valid reminder producers keep their existing recovery confirmation, Bank freshness/stage and update policy rules. `AppNotificationRouter` splits valid events into independent desktop and mobile channels before checking desktop presentation mode. A separate semantic receipt permits a first desktop display or Bark service acceptance to acknowledge the original event once; it never consumes the other channel or desktop unread state.

`BarkNotificationController` owns a bounded serial queue, configuration generation and cancellation. Core payload and receipt types share sanitized cross-platform fixtures under `contracts/bark/`. Mobile attempt receipts are atomically persisted before HTTP to avoid automatic replay after a crash; acceptance is recorded separately. Recovery/account cancellation excludes account-independent software updates. Explicit update snooze captures a new reminder generation; ordinary channel/config changes cannot create one.

Native secure stores use Keychain or current-user Credential Manager behind injectable interfaces. Native HTTP adapters use the fixed official Bark HTTPS endpoint, prohibit redirects, limit payload/response size and time out without automatic retries. The fifth settings page exposes explicit save/clear/test and sanitized status, preserving existing update navigation. See the [approved design](superpowers/specs/2026-10-23-bark-mobile-push-design.md), [implementation plan](superpowers/plans/2026-10-23-bark-mobile-push.md) and [privacy](PRIVACY.md).
