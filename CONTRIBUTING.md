# Contributing to QuotaBar

The current product is the standalone macOS menu bar/floating quota app. Native source/resources/tests are in `native/`; packaging and transaction install are in `scripts/`. Windows standalone is not implemented.

Develop on `codex/<type>/<kebab-case>`. Run `./governance doctor` before changes and `./governance check all` before pushing. Use English Conventional Commit headers/PR titles. Do not bypass hooks, weaken checks or overwrite published assets. Release Please owns product versions.

Read [development progress](docs/PROJECT_PROGRESS-standalone-app.md) and resume the project board before every continuation. Update the roadmap and generated board through its utility after milestones. Keep README, installation, architecture, troubleshooting, privacy and validation aligned with final behavior. Preserve historical release facts.

Protect owned-process shutdown, isolated login and rename-safe installation. Add meaningful regression coverage for behavior changes; distinguish unit tests, CI and device evidence. Packaging needs Xcode, Apple Silicon and official `codex-cli 0.144.1`. Menu bar artwork is a transparent vector template; AppIcon.icns contains the existing full application artwork.

Never include credentials, account data, private screenshots, build caches or runtime binaries in source commits. Exact-tag app/DMG builds and public-download verification are required for publication; document untested OS/device matrices.
