# Troubleshooting

- First launch blocked: the published v0.5.0 package is locally signed, not Developer ID notarized. Inspect the source and signature and use macOS Privacy & Security to permit the app if appropriate.
- No quota: open Settings, finish official browser login, then refresh. The standalone account may differ from the desktop account.
- Offline or stale data: check connectivity, refresh or reload the bundled runtime. Cached quota does not imply a successful current query.
- Duplicate older entry: use the [migration installer](MACOS_STANDALONE.zh-CN.md). The old plugin must not remain active.
- Login startup: status may require approval in macOS Login Items. The app reads the actual Service Management status.
- Quit: use Quit or Cmd-Q; closing a settings window only hides it. Owned runtime processes should exit with the app.

For bugs, include the app version, macOS version/architecture and reproduction steps. Omit credentials, personal account details and unrelated screenshots.
