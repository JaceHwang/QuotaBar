# Repository governance

`./governance doctor` checks hooks and repository integration. Feature/fix/refactor work uses `codex/<type>/<kebab-case>`. Conventional Commit headers and PR titles are required. `./governance check all` validates the standalone tree, source isolation, documentation links, runtime boundary, native tests, installer transaction tests and signing selection.

Release Please owns product versions. Staged macOS publication builds from the exact clean release tag, verifies the bundled runtime/signature/digests and source snapshot, then uploads new asset names without replacing existing assets. Windows standalone is planned and has no current release adapter.

Old plugin-specific validators and frozen binary checks were removed with the old product, and replaced with the standalone product's full verification boundaries. Published historical assets and tags remain immutable on GitHub.
