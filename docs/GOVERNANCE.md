# Repository governance

This repository vendors the executable policy from
[`JaceHwang/repo-governance`](https://github.com/JaceHwang/repo-governance).
The tracked `.governance/VERSION` records the template revision. The policy is
local to this repository: cloning it never depends on a central service.

## Daily development

Create a short-lived branch named `codex/<type>/<kebab-case>`, for example
`codex/fix/retry-token-read`. Allowed types and English Conventional Commit
headers are checked locally and again in pull-request CI.

Run these commands before working and before pushing:

```sh
./governance doctor
./governance check all
```

`governance doctor` repairs nothing by itself. If it reports inactive hooks,
run `./governance bootstrap`, then rerun doctor. Do not use `--no-verify`, work
directly on `main`, or manually change a product version in an ordinary commit.

## Versions and releases

Release Please manages the product version through `.release-please-manifest.json`.
A candidate value in the working tree is not evidence of a published stable release. A Release Please PR updates the product version
in `version.txt`, the plugin manifest, the macOS bundle plist, the Windows
`VersionPrefix`, and `CHANGELOG.md` together.

Stable tags are `vX.Y.Z`. `fix`, `perf`, and `revert` changes produce a patch;
`feat` produces a minor; breaking changes produce a minor while the project is
`0.x` and a major from `1.0.0` onward. Documentation, tests, build, CI, style,
and chore changes do not release by default.

Release Please creates a draft GitHub Release. This project uses staged platform
publishing: a platform must build from the exact tag/SHA, pass its verifier, and
must not overwrite an existing asset. The macOS publisher selects the macOS runner and delegates to
the versioned build/package/verifier scripts. Windows uses its evidence-bound workflow and requires
the exact tagged commit, clean checkout, installer verification, checksum, provenance, and recorded
real-device acceptance before upload.

Pre-releases are only made from `codex/prerelease/alpha`,
`codex/prerelease/beta`, or `codex/prerelease/rc`; stable releases still come
from `main`.

## Published platform baselines

The current published baselines are macOS v0.4.0 and Windows v0.4.1. Their release notes and uploaded
provenance are the source of truth for those assets. Ordinary feature commits retain the current
released version; Release Please performs the next version bump. Rebuild every platform asset from
the exact release tag and rerun its required checks before upload. Never manually move a stable tag,
overwrite a published asset, or use a dirty local build as exact release provenance.
