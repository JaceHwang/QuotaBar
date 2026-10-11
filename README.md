# Codex Quota

Independent macOS menu bar app for Codex account quota. It uses a bundled official runtime and isolated login, so the Codex desktop UI and plugin system are not required.

[Latest release v0.5.1](https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.5.1) · [Apple Silicon DMG](https://github.com/JaceHwang/codex-usage-sidebar/releases/download/v0.5.1/codex-quota-v0.5.1-macos-arm64.dmg) · [中文](README.zh-CN.md)

Two menu bar lines show remaining quota and reset dates. Click for details; use settings for official login, refresh, theme, language and login startup. Credentials stay in a local isolated directory. Quota percentages are not cash balances.

The published package is locally signed, not Developer ID notarized. Apple Silicon, declared macOS 14+, device-tested on macOS 27.0. Windows standalone remains planned.

See [installation](docs/MACOS_STANDALONE.zh-CN.md), [architecture](docs/ARCHITECTURE.md), [progress](docs/PROJECT_PROGRESS-standalone-app.md), and [validation](docs/validation/macos-standalone.md).

## Development

```bash
./governance doctor
./governance check all
CUS_RUNTIME_BINARY=/path/to/codex bash scripts/build-macos-standalone.sh
```

Requires Xcode and official `codex-cli 0.144.1` for packaging. Runtime, native source and tests live in `native/`; installation and release tools live in `scripts/`. Versions are updated only through Release Please. Historical plugin code and assets remain available in Git history and previous GitHub releases.
