# Security Policy

## Supported versions

Security fixes are applied to the latest published release.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability. Use GitHub's private vulnerability reporting
for this repository:

https://github.com/JaceHwang/codex-usage-sidebar/security/advisories/new

Include the affected version, impact, reproduction steps, and any suggested mitigation. You should
receive an initial response within seven days. Please allow a reasonable remediation window before
public disclosure.

## Security boundaries

QuotaBar must remain outside the official Codex application; it must not inject into, modify,
or re-sign that app. Authentication must remain isolated from the normal `~/.codex` home. QuotaBar must not upload quota data, add telemetry, inspect conversation or repository content, or
bypass macOS privacy controls. See [docs/PRIVACY.md](docs/PRIVACY.md) for the data-flow model.

The menu bar/floating preferences are local. Rename-safe updates retain the isolated account; use supported sign-out before credential cleanup. See [installation](docs/MACOS_STANDALONE.zh-CN.md) for user-level paths and recovery.
