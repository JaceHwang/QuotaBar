# QuotaBar v0.7.0 Windows standalone

Published 2026-10-13: [release](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.7.0). Latest release; Windows 11 x64. macOS remains at v0.6.0.

Source: immutable v0.7.0 at 65286812ddc335b97d15fa35b1932cbc344394da. Feature PR #32 and generated Release Please PR #33 merged after required checks. Windows functionality and final UI have user-reported complete device acceptance. Exact versioned binaries were separately exercised on native Windows CI, not claimed as a separate device install.

The app includes the official 0.144.1 runtime and self-contained .NET 10, independent credentials, tray/float/detail/settings/startup, common circular application/tray icon, compact quota gradients, simplified statistics, days/hours above full expiry timestamps, and inline X+Tibo. Runtime stderr cleanup is bounded. Windows packages are unsigned.

Assets:

- QuotaBar-0.7.0-windows-x64.zip
- QUOTABAR-WINDOWS-INSTALL.zh-CN.md
- QUOTABAR-WINDOWS-PROVENANCE.json
- QUOTABAR-WINDOWS-VERIFICATION.json
- QUOTABAR-WINDOWS-SHA256SUMS.txt

ZIP SHA256: 5451992bf76a834da6fa764df1cb798abfe0bc0277fc91c10bfe75712c35787d.

[Native publisher CI](https://github.com/JaceHwang/codex-usage-sidebar/actions/runs/38345901775) passed complete payload/source checks, actual runtime startup/exit and per-user install/upgrade/rollback/uninstall. All five uploaded assets were downloaded and checked again at the exact source tag using `python3 scripts/verify-windows-standalone-release.py v0.7.0 .dist/published-windows-v0.7.0`. Verification passed; no prior release assets were replaced.

Extract the entire ZIP and run QuotaBar/setup/QuotaBar.Setup.exe. See the [Windows guide](../WINDOWS_STANDALONE.zh-CN.md) for installation and recovery. Upgrade, rollback and uninstall preserve account/settings data.
