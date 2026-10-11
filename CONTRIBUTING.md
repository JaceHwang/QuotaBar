# Contributing

Develop on `codex/<type>/<kebab-case>`, never directly on `main`. Run `./governance doctor` before changes and `./governance check all` before pushing. Do not bypass hooks, weaken checks or overwrite published assets.

The current product is the standalone macOS app. Native source/tests live in `native/`. Packaging requires Xcode, Apple Silicon and official Codex 0.144.1. Keep owned-process shutdown, isolated login and release source verification intact. Add meaningful regression coverage when behavior changes.

Read [development progress](docs/PROJECT_PROGRESS-standalone-app.md) and resume the project board before continuing work. Update both after milestones. Distinguish local tests, CI, device observations and publication.

Use English Conventional Commit headers and PR titles. Describe behavior, why it changed, verification and material limits. Versions are managed only by generated Release Please PRs. Never include credentials, account data, private screenshots, build caches or runtime binaries in source commits.
