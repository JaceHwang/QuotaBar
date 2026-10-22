# QuotaBar repository governance

Updated: 2026-10-12.

Run `./governance doctor` before changes. Develop on `codex/<type>/<kebab-case>`, never directly on main. Use English Conventional Commit headers and PR titles. Before pushing run `./governance check all`; hooks and GitHub checks enforce the repository policy. Do not bypass hooks or weaken adapters.

The current checks cover native tests, installer migration/transaction recovery, signing identity selection, source isolation, JSON, privacy, links and shell syntax. UI source changes require relevant behavior/resource checks and accurate device evidence. Read [progress](PROJECT_PROGRESS-standalone-app.md) and resume `.project-board/` before continuing; update both at milestones.

Release Please alone changes product versions and creates the release tag. Review the generated manifest/version/changelog and CI before merging. Staged macOS publication uses the exact clean tag:

```bash
CUS_RUNTIME_BINARY=/path/to/codex bash scripts/package-macos-standalone-release.sh vX.Y.Z
python3 scripts/verify-macos-standalone-release.py vX.Y.Z .dist/release/macos-arm64
```

The verifier checks the QuotaBar bundle, icon metadata, strict signatures, runtime/application hashes, version and tagged source snapshot. Upload all five assets without replacement, publish, then download and verify the public assets again from the same tag. Installers and guides must match their release. Do not commit build caches or installer binaries to source Git.

Historical release tags/assets remain immutable. Update current docs and release catalog after publication, while preserving historical facts. Local tests, CI, device acceptance and release verification are separate states. Windows publication must be built and installation-tested on native Windows CI; record device acceptance separately. Public Windows packages are unsigned. Developer ID notarization remains pending for macOS.
