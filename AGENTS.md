<!-- repo-governance:start -->
## Repository governance

- Run `./governance doctor` before the first code-changing action in a task. If hooks are inactive, run `./governance bootstrap` and repeat doctor.
- Never develop or commit directly on `main`; use `codex/<type>/<kebab-case>`.
- Use English Conventional Commit headers and Conventional Commit PR titles. PR background and verification may be written in Chinese.
- Never use `--no-verify`, conceal failed tests, overwrite a published release asset, or edit product versions in ordinary commits.
- Ordinary pushes run `./governance check sync`: mandatory fast checks and native device tests (`check local`). Windows uses Git Bash, Python and .NET 10; macOS uses Xcode, Python 3 and .NET 10.
- To synchronize unfinished work, use `QUOTABAR_DRAFT_SYNC=1 git push` only for `codex/<type>/<slug>` development branches and keep the PR in draft. Fast checks must pass; native tests still run and any failure must be recorded in the PR. This mode is forbidden in CI and for main, prerelease branches or tags.
- GitHub CI runs the complete macOS and Windows verification for every development push and PR. Both platform checks and governance policy are required for merging into main or prerelease branches. Run `./governance check all` on macOS/CI for the existing cross-platform suite.
- Before release, record both physical-device results against the same source commit and candidate hashes. Publishing requires successful dual-platform CI for the exact tagged commit. Release product versions only through the generated Release Please PR.
<!-- repo-governance:end -->

## Development progress

- Before every development, continuation, fix, validation or release task, read `docs/PROJECT_PROGRESS-standalone-app.md` and resume `.project-board/` using the installed tracking-project-progress skill utility when available. If it is unavailable, read `.project-board/board.md` directly and report the limitation; never hand-edit its generated files.
- Reconcile the progress with live code, Git status and verification evidence before selecting work. The standalone-app document is the detailed roadmap; the board is the current recovery snapshot. Historical tasks on the board do not certify standalone-app completion.
- Update the roadmap task status, evidence, decisions, blockers and next action after each meaningful milestone, before interruption/handoff and before ending a development session. Update the board through its utility and validate it when available.
- Distinguish planned, implemented, tested on CI, tested on a device and released states. Record tests that were not run and do not mark a platform complete based on another platform's result.
- Follow the user's latest authorization for implementation, installation and release. The current objective authorizes Windows standalone implementation, macOS feature parity and candidate packaging/installation testing. Public release requires explicit release authorization; record current platform scope in the standalone roadmap.

## Dual-device development

- Follow [the synchronization guide](docs/DEVELOPMENT_SYNC.zh-CN.md). Use a shared feature branch for sequential handoff; concurrent device work uses separate development branches and PRs into the feature branch.
- Fetch and use `git pull --ff-only` before continuing on the other device. Preserve other developers' commits, and resolve divergence explicitly.
- Record source SHA, platform, candidate hash and actual device result in the draft PR. A CI pass and a physical-device pass are separate evidence.


