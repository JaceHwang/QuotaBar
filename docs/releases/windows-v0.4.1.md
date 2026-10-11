# Codex Usage Sidebar Windows v0.4.1

The formal Windows release is available from the [v0.4.1 GitHub Release](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.4.1). The existing macOS v0.4.0 release remains unchanged.

## Requirements

- Windows 11 AMD64/x64
- Codex desktop installed and signed in
- No fixed Codex desktop version; an unknown titlebar structure remains hidden

## Assets

- `codex-usage-sidebar-v0.4.1-windows-x64-setup.exe`
- `WINDOWS-V041-SHA256SUMS.txt`
- `WINDOWS-V041-PROVENANCE.json`

Verify the installer SHA-256 against `WINDOWS-V041-SHA256SUMS.txt` before running it. The current-user installer is intentionally unsigned.

## Included fixes

- Automatic placement rescans the titlebar after selecting Automatic mode or double-clicking the indicator.
- A freely positioned indicator opens its detail card above the button whenever necessary to avoid covering it.
- Dark-theme settings-menu borders and colors follow the active theme.
- Foreground return and current Codex titlebar discovery are more reliable.
- The obsolete Lock Safe Docker tray option is removed.
