#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
tag="${1:?release tag required}"
[[ "$tag" == "v$(cat version.txt)" ]]
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "$tag^{commit}")" ]]
[[ -z "$(git status --porcelain --untracked-files=no)" ]]
asset_dir="$repo_root/.dist/release/macos-arm64"
mkdir -p "$asset_dir"
if [[ -z "${CUS_RUNTIME_BINARY:-}" ]]; then
  runtime_dir="$repo_root/.dist/standalone-runtime-0.144.1"
  mkdir -p "$runtime_dir"
  curl --fail --location --silent --show-error https://github.com/openai/codex/releases/download/rust-v0.144.1/codex-aarch64-apple-darwin.tar.gz -o "$runtime_dir/runtime.tar.gz"
  tar -xzf "$runtime_dir/runtime.tar.gz" -C "$runtime_dir"
  export CUS_RUNTIME_BINARY="$runtime_dir/codex-aarch64-apple-darwin"
fi
export CUS_RELEASE_TAG="$tag"
log="$repo_root/.dist/standalone-release-build.log"
bash scripts/build-macos-standalone.sh | tee "$log"
candidate="$(sed -n 's/^Standalone candidate: //p' "$log" | tail -1)"
test -d "$candidate/Codex Quota.app"
cp "$candidate/Codex-Quota-macos-arm64.dmg" "$asset_dir/codex-quota-$tag-macos-arm64.dmg"
cp "$candidate/PROVENANCE.json" "$asset_dir/CODEX-QUOTA-PROVENANCE.json"
cp scripts/install-macos-standalone.py "$asset_dir/install-macos-standalone.py"
cp docs/MACOS_STANDALONE.zh-CN.md "$asset_dir/CODEX-QUOTA-INSTALL.zh-CN.md"
(cd "$asset_dir" && shasum -a 256 codex-quota-*.dmg CODEX-QUOTA-PROVENANCE.json install-macos-standalone.py CODEX-QUOTA-INSTALL.zh-CN.md > CODEX-QUOTA-SHA256SUMS.txt)
