# Troubleshooting

> **Current releases:** macOS v0.4.0 and Windows v0.4.1. Use only the assets and checksums attached
> to the matching GitHub Release. Current controls and platform boundaries are documented in
> [CURRENT_FEATURES](CURRENT_FEATURES.md).


## Windows setup and runtime

The v0.4.1 installer is published in the
[v0.4.1 GitHub Release](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.4.1).
After installation, run `CodexUsageSidebar.Control.exe status` (or start a new Codex task) to see local runtime state. The
generic selector and signed compatibility update recover automatically; ordinary users do not edit
selector files. `placement=Fallback` means the automatic safe dock is intentionally visible while
titlebar compatibility recovers; it is not a reason to edit selector files. If status says
validation is needed, use the opt-in default-redacted diagnostic export from the control command and
share only the generated redacted ZIP. The companion never uploads diagnostics automatically.

### Startup exits with `InvalidSelectorCatalogException`

If the Windows log says `selectors.json is not a valid schema-v2 selector catalog` and the installed
file reports `schemaVersion: 1` or `status: device-test`, the payload is an obsolete or malformed
package. This is a packaging defect, not a Codex titlebar compatibility failure. Do not edit the
selector file by hand: the selector is loaded before the HTTPS compatibility updater can run. Use
the corrected Windows release installer to replace `%LOCALAPPDATA%\CodexUsageSidebar\Current`, then
start a new Codex task. The release verifier now rejects schema-v1 selectors before an installer can
be published, and newer runtimes fall back to the built-in safe catalog instead of exiting.

### SmartScreen shows Unknown publisher

The Windows x64 setup is intentionally unsigned. Verify the SHA-256 against
`WINDOWS-V041-SHA256SUMS.txt` first. If it matches, **Unknown publisher** is expected: select
**More info**, then **Run anyway**. If it does not match, do not run the setup; download it again
from the v0.4.1 release. Never disable Defender, SmartScreen, antivirus, or system policy.

### The overlay is hidden after a Codex upgrade

The Windows selector does not require a particular Codex file version anymore. A hidden overlay
means the current title-bar UI Automation structure could not be proven safe; collect only a
default-redacted diagnostic and do not force the overlay to attach. The bounded coordinate fallback
is still limited to the measured build `151.0.7922.76`; newer builds use the generic semantic
selector and automatic safe dock while compatibility recovers. `runtime=unavailable` means no approved runtime
was found, `runtime=stopped` means the approved runtime is installed but not running, and
`runtime=running` means it is active.

Windows 用户如果看到“未知发布者”，只有在 SHA-256 匹配后才选择“更多信息”和“仍要运行”；不匹配时不要运行文件。

## No quota control appears

1. Open Codex desktop and bring its main window to the foreground.
2. Start a new Codex task so the `SessionStart` hook runs.
3. Verify the companion:

   ```bash
   "$HOME/Library/Application Support/CodexUsageSidebar/sidebar-control.sh" status
   ```

4. Repair if the service is missing or stale:

   ```bash
   "$HOME/Library/Application Support/CodexUsageSidebar/sidebar-control.sh" repair
   ```

If status reports `hidden:no-snapshot`, verify the isolated login described next.

## Isolated Codex home is not logged in

The companion does not use the normal `~/.codex` credentials. Authorize its private home:

```bash
plugin_home="$HOME/Library/Application Support/CodexUsageSidebar/CodexHome"
env CODEX_HOME="$plugin_home" codex login
env CODEX_HOME="$plugin_home" codex login status
```

Then repair the companion or wait for its app-server client to reconnect.

## Status says `accessibility=required`

Enable **Codex Usage Sidebar** in
`System Settings -> Privacy & Security -> Accessibility`, then run repair. Do not enable only Codex;
the separately installed companion needs its own entry.

The stable designated requirement reduces permission churn, but macOS can still request approval
after signing or security-policy changes.

If a locally verified layout moves only after plugin reinstall, compare the visible version badge
with `version=` from status and check that status reports the active LaunchAgent PID. Repair copies
and re-signs the payload with the stable local identity; do not re-sign the official Codex app.

## Placement overlaps or Automatic immediately becomes Free

Automatic first searches safe space. When none fits it uses the default
position; an interactive control overlapping that default causes a persistent switch to Free.
Drag the indicator, or explicitly select Automatic again after freeing titlebar space. This behavior
is separate from stale-data/background-host hiding.

An earlier local 0.4.0 build treated any AX action as clickable: a 1920×46 `AXGroup` with only
`AXShowMenu`/`AXScrollToVisible` then blocked the whole toolbar. Current code excludes those auxiliary
actions; real button roles and `AXPress`/`AXPick` controls remain obstacles. A shared version badge
alone cannot identify which local build is installed.

Check the live process using the installed control script's `status`. Example fields:

```text
version=0.4.0 runtime=shown placement=content-header mode=automatic
indicator=1123,1003,209,46 anchor_scan=...obstacles:13,freeFallback:false,...edge:1340
```

These are sample values, not expected coordinates/counts for every layout. `mode` is the actual
mode; `freeFallback` is the current scan recommendation, including when already in Free. Anchor
source/edge are preferences, not proof of final collision-free placement; do not require
`x + width = edge - 8` after free-slot search or in manual modes.

For a targeted role/bounds diagnostic (no label text), run:

```bash
CUS_DIAGNOSTIC_OBSTACLES=1 "$HOME/Library/Application Support/CodexUsageSidebar/Codex Usage Sidebar.app/Contents/MacOS/CodexUsageSidebar" --diagnostic-once
```

The one-shot probe uses the default width, so confirm actual-width behavior with the managed
runtime-state file and a user-provided cropped screenshot. Repair/reinstall the intended local
payload if code and installed build differ; preserve signing identity and do not re-sign Codex.

## Detail pin, detail lock and position lock

Click-pinned detail dismisses on outside click. The header lock keeps it open until unlocked,
subject to normal visibility gates. Locked **position mode** only prevents dragging the indicator.
The position selector can temporarily suppress the detail card. These are separate controls.

## Detail size, menus and update behavior

Sparse details keep an eight-row natural minimum; additional rows may grow to the height cap.
Use the resize grip to adjust the scrolling region. Long English detail labels can be clipped in
the fixed-width row column; the native documentation fixtures show the current rendering rather
than edited replacement text. Check for updates opens GitHub Releases; it does not install an update.
Reload restarts the companion; Quit terminates it (the configured LaunchAgent can start it again).

## Data looks old

The indicator dims after two minutes and hides after five. Confirm the isolated login is active and
Codex is online, then bring Codex to the foreground. The client automatically recovers from a
stalled stream; repair forces an immediate clean restart.

Logs are stored at:

```text
~/Library/Application Support/CodexUsageSidebar/Data/sidebar.log
~/Library/Application Support/CodexUsageSidebar/Data/sidebar-error.log
```

Remove credentials and account identifiers before sharing log excerpts.

## The plugin language does not match Codex

Run status and inspect the sanitized language fields:

```text
language=traditionalChinese language_source=process
```

The companion follows Codex's effective displayed locale rather than maintaining a separate
language selector. `process` is authoritative while Codex is running; `preferences` and `system`
are startup fallbacks. Simplified Chinese, Traditional Chinese, and English map directly, while
every other locale displays English.

After changing Codex's language setting, allow up to one second for a running renderer change. If
Codex itself still shows the previous language, restart Codex so its renderer applies the new
setting, then run status again. If status remains inconsistent, repair the companion. Raw process
arguments are never included in status or logs.

## Update or reset

Normal update:

```bash
codex plugin marketplace upgrade codex-usage-sidebar
codex plugin add codex-usage-sidebar@codex-usage-sidebar
```

Full reset:

```bash
"$HOME/Library/Application Support/CodexUsageSidebar/sidebar-control.sh" uninstall
codex plugin marketplace upgrade codex-usage-sidebar
codex plugin add codex-usage-sidebar@codex-usage-sidebar
```

Start a new Codex task afterward.

## Reporting a bug

Use the repository bug form. Include macOS version, Codex build, plugin version, sanitized status
output, the relevant log excerpt, and exact reproduction steps. Crop screenshots to the affected
titlebar area; never attach a full desktop containing unrelated projects or conversations.
