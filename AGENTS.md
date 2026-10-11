<!-- repo-governance:start -->
## Repository governance

- Run `./governance doctor` before the first code-changing action in a task. If hooks are inactive, run `./governance bootstrap` and repeat doctor.
- Never develop or commit directly on `main`; use `codex/<type>/<kebab-case>`.
- Use English Conventional Commit headers and Conventional Commit PR titles. PR background and verification may be written in Chinese.
- Never use `--no-verify`, weaken checks, overwrite a published release asset, or edit product versions in ordinary commits.
- Run `./governance check all` before pushing. Release product versions only through the generated Release Please PR.
<!-- repo-governance:end -->

## Development progress

- Before every development, continuation, fix, validation or release task, read `docs/PROJECT_PROGRESS-standalone-app.md` and resume `.project-board/` using the installed tracking-project-progress skill utility when available. If it is unavailable, read `.project-board/board.md` directly and report the limitation; never hand-edit its generated files.
- Reconcile the progress with live code, Git status and verification evidence before selecting work. The standalone-app document is the detailed roadmap; the board is the current recovery snapshot. Historical tasks on the board do not certify standalone-app completion.
- Update the roadmap task status, evidence, decisions, blockers and next action after each meaningful milestone, before interruption/handoff and before ending a development session. Update the board through its utility and validate it when available.
- Distinguish planned, implemented, tested on CI, tested on a device and released states. Record tests that were not run and do not mark a platform complete based on another platform's result.
- Follow the user's latest authorization for implementation, installation and release. The current objective authorizes completing the macOS standalone application and packaging/install testing; it does not authorize a public release or Windows implementation.


