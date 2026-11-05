#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1])
version=(root/'version.txt').read_text().strip()
match=re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-beta\.([1-9][0-9]*))?',version)
assert match and len(version)<=128 and all(int(n)<=65534 for n in match.groups()[:3])
assert not match.group(4) or int(match.group(4))<=2147483647
assert json.loads((root/'.release-please-manifest.json').read_text())['.']==version
config=json.loads((root/'release-please-config.json').read_text())
assert config['packages']['.']['extra-files']==[{'type':'generic','path':'version.txt'}]
assert config['draft'] and config['force-tag-creation']
for channel in ['alpha','beta','rc']:
 config=json.loads((root/'.governance/release'/f'{channel}.json').read_text())
 assert config['versioning']=='prerelease' and config['packages']['.']['prerelease-type']==('beta.1' if channel=='beta' else channel)
 if channel=='beta': assert config['packages']['.']['extra-files']==[{'type':'generic','path':'version.txt'}]
policy=(root/'.governance/policy.sh').read_text()
assert "RELEASE_MODE=staged" in policy and "RELEASE_PLATFORMS='macos-arm64 windows-x64'" in policy
for name in ['check-fast','check-full','build-release','verify-release']:
 assert (root/'.governance/project'/name).stat().st_mode & 0o111
full=(root/'.governance/project/check-full').read_text()
assert 'swift test --package-path native' in full and 'test-macos-standalone-install.py' in full
assert 'test-signing-identity.sh' in full
build=(root/'scripts/build-macos-standalone.sh').read_text()
assert 'CUS_RELEASE_TAG' in build and 'status --porcelain --untracked-files=no' in build
verify=(root/'scripts/verify-macos-standalone-release.py').read_text()
for required in ["codesign", "sourceSnapshotSha256", "runtimeSignedSha256", "applicationSignedSha256", "CFBundleShortVersionString"]:
 assert required in verify
PY
printf 'Standalone repository governance integration tests passed\n'
