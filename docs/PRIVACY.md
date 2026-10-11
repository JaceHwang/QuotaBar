# Privacy model

Scope: published macOS v0.4.0 and Windows v0.4.1 behavior. Windows uses a separate UIA/runtime and
signed compatibility-update boundary.

## Data read

- Quota windows, reset times, plan, Credits, Bank credits/status/expiry, seven-day Tokens and account
  display identity from the local Codex app-server over JSON-RPC/stdio.
- Codex window geometry, eligible titlebar-control labels, roles, actions and bounds for placement.
  Non-actionable groups provide structural pane geometry; conversation bodies are not read.
- Process/bundle metadata for Codex discovery, effective language and light/dark appearance.
- Mouse-down events while the relevant menus or pinned detail interactions are active, solely to
  detect an outside click and dismiss those surfaces. Free-mode dragging uses pointer events.

## Authentication

The companion uses the separate home at
`~/Library/Application Support/CodexUsageSidebar/CodexHome`.
Credentials there are created through official `codex login`. Installation does not copy the normal
`~/.codex/auth.json`. Do not put credentials or account data in documentation screenshots.

## Data written

- Application/control scripts under `~/Library/Application Support/CodexUsageSidebar/`.
- Isolated authentication/configuration under `CodexHome`; runtime state/logs under `Data`.
- User LaunchAgent at `~/Library/LaunchAgents/com.jace.codex-usage-sidebar.plist`.
- UserDefaults position preference `com.jace.codex-usage-sidebar.indicator-placement.v1` in the
  companion's defaults domain: mode, active display identifier and normalized per-display positions.
- Managed status contains PID, version, time, visibility, mode, mapped language/source, anchor,
  geometry, scan/obstacle counts and the current `freeFallback` decision. It does not contain quota
  values, account identifiers, control labels or conversation content.
- Opt-in `CUS_DIAGNOSTIC_OBSTACLES=1` adds AX role/action names and control rectangles only.

## Data not collected

Conversation bodies, repository file contents, browser cookies, keyboard input, click-history logs,
normal Codex-home credentials, telemetry and advertising identifiers are not collected by this companion.
It does not scrape social feeds or web pages. Raw locale-discovery process arguments are not persisted.

## Network and external actions

The companion adds no analytics server. Official app-server networking for authenticated account
and quota data follows Codex's own behavior. The GitHub footer opens the repository; Check for
updates opens its Releases page in the browser and does not silently install updates. Published
Windows compatibility updates use their separate signed HTTPS/catalog verification contract.

## Accessibility and input boundaries

macOS grants the permission. The companion does not bypass the prompt, modify the Codex bundle,
or synthesize typing/clicks. Geometry filters bound titlebar reads; button roles and direct press/pick
actions identify interaction targets. Generic menu/scroll helper actions do not turn structural
containers into buttons. Temporary outside-click observers are removed when the corresponding
surface closes. This is not a claim of zero global mouse observation: such observers are part of
the current outside-dismiss behavior.
