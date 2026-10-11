#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_root="$repo_root/plugins/codex-usage-sidebar/native"
runtime="${CUS_RUNTIME_BINARY:-$(command -v codex)}"
if [[ -n "${CUS_RELEASE_TAG:-}" ]]; then
  [[ "$CUS_RELEASE_TAG" == "v$(cat "$repo_root/version.txt")" ]]
  [[ "$(git -C "$repo_root" rev-parse HEAD)" == "$(git -C "$repo_root" rev-parse "$CUS_RELEASE_TAG^{commit}")" ]]
  [[ -z "$(git -C "$repo_root" status --porcelain --untracked-files=no)" ]]
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
source "$repo_root/plugins/codex-usage-sidebar/scripts/select-signing-identity.sh"
output="$repo_root/.dist/standalone-macos"
mkdir -p "$output"
stage="$(mktemp -d "$output/build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Codex Quota.app"
version="$(cat "$repo_root/version.txt")"
runtime_version="$("$runtime" --version)"
[[ "$runtime_version" == 'codex-cli 0.144.1' ]] || { echo 'Expected validated codex-cli 0.144.1' >&2; exit 65; }
[[ "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon required' >&2; exit 65; }
xcrun swift test --package-path "$package_root"
xcrun swift build -c release --arch arm64 --package-path "$package_root"
bin="$(xcrun swift build -c release --arch arm64 --show-bin-path --package-path "$package_root")"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
install -m 755 "$bin/CodexUsageSidebar" "$app/Contents/MacOS/CodexUsageSidebar"
install -m 755 "$runtime" "$app/Contents/Helpers/codex"
ditto "$bin/CodexUsageSidebar_CodexUsageSidebar.bundle" "$app/Contents/Resources/CodexUsageSidebar_CodexUsageSidebar.bundle"
curl --fail --location --silent --show-error https://raw.githubusercontent.com/openai/codex/rust-v0.144.1/LICENSE -o "$app/Contents/Resources/CODEX-LICENSE"
curl --fail --location --silent --show-error https://raw.githubusercontent.com/openai/codex/rust-v0.144.1/NOTICE -o "$app/Contents/Resources/CODEX-NOTICE"
python3 - "$app" "$version" "$runtime_version" "$repo_root" <<'PY'
import hashlib,json,pathlib,plistlib,subprocess,sys
app=pathlib.Path(sys.argv[1])
with (app/'Contents/Info.plist').open('wb') as f:
 plistlib.dump({'CFBundleIdentifier':'com.jace.codex-quota','CFBundleName':'Codex Quota','CFBundleDisplayName':'Codex Quota','CFBundleExecutable':'CodexUsageSidebar','CFBundlePackageType':'APPL','CFBundleShortVersionString':sys.argv[2],'CFBundleVersion':'1','LSMinimumSystemVersion':'14.0','LSUIElement':True,'CUSStandalone':True},f)
import os
release_tag=os.environ.get('CUS_RELEASE_TAG')
provenance={'kind':'release' if release_tag else 'local-development-candidate','sourceCommit':subprocess.check_output(['git','-C',sys.argv[4],'rev-parse','HEAD'],text=True).strip(),'workingTreeDirty':bool(subprocess.check_output(['git','-C',sys.argv[4],'status','--porcelain','--untracked-files=no'],text=True).strip()),'version':sys.argv[2],'runtimeVersion':sys.argv[3],'runtimeSource':'https://github.com/openai/codex/releases/tag/rust-v0.144.1','runtimeUnsignedSha256':hashlib.sha256((app/'Contents/Helpers/codex').read_bytes()).hexdigest(),'releaseTag':release_tag}
repo=pathlib.Path(sys.argv[4])
paths=[repo/'version.txt',repo/'plugins/codex-usage-sidebar/native/Package.swift',repo/'scripts/build-macos-standalone.sh',repo/'scripts/install-macos-standalone.py']
for folder in ['Sources','Tests']:
 paths.extend((repo/'plugins/codex-usage-sidebar/native'/folder).rglob('*'))
source_hashes={str(p.relative_to(repo)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths) if p.is_file()}
source_snapshot=json.dumps(source_hashes,sort_keys=True,indent=2)+'\n'
(app/'Contents/Resources/SOURCE-SNAPSHOT.json').write_text(source_snapshot)
provenance['sourceSnapshotSha256']=hashlib.sha256(source_snapshot.encode()).hexdigest()
(app/'Contents/Resources/PROVENANCE.json').write_text(json.dumps(provenance,indent=2)+'\n')
PY
identity="$(select_signing_identity)"
codesign --force --sign "$identity" "$app/Contents/Helpers/codex"
python3 - "$app" <<'PY'
import hashlib,json,pathlib,sys
app=pathlib.Path(sys.argv[1]);path=app/'Contents/Resources/PROVENANCE.json';info=json.loads(path.read_text())
info['runtimeSignedSha256']=hashlib.sha256((app/'Contents/Helpers/codex').read_bytes()).hexdigest()
info['applicationUnsignedSha256']=hashlib.sha256((app/'Contents/MacOS/CodexUsageSidebar').read_bytes()).hexdigest()
path.write_text(json.dumps(info,indent=2)+'\n')
PY
codesign --force --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
candidate="$output/candidate-$(date +%Y%m%d-%H%M%S)"
mkdir "$candidate"
ditto "$app" "$candidate/Codex Quota.app"
python3 - "$candidate" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);app=root/'Codex Quota.app';info=json.loads((app/'Contents/Resources/PROVENANCE.json').read_text())
info['applicationSignedSha256']=hashlib.sha256((app/'Contents/MacOS/CodexUsageSidebar').read_bytes()).hexdigest()
(root/'PROVENANCE.json').write_text(json.dumps(info,indent=2)+'\n')
PY
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname 'Codex Quota' -srcfolder "$stage" -format UDZO "$candidate/Codex-Quota-macos-arm64.dmg"
hdiutil verify "$candidate/Codex-Quota-macos-arm64.dmg"
shasum -a 256 "$candidate/Codex-Quota-macos-arm64.dmg" > "$candidate/SHA256SUMS.txt"
printf 'Standalone candidate: %s\n' "$candidate"
