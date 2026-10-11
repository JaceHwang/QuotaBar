#!/usr/bin/env python3
"""Verify published standalone payload against its immutable source tag."""
import hashlib, json, pathlib, plistlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
tag, assets = sys.argv[1], pathlib.Path(sys.argv[2]).resolve()
def run(*args):
    return subprocess.check_output(args)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
commit = run('git', '-C', str(root), 'rev-parse', f'{tag}^{{commit}}').decode().strip()
assert commit == run('git', '-C', str(root), 'rev-parse', 'HEAD').decode().strip()
assert tag == 'v' + (root / 'version.txt').read_text().strip()
subprocess.run(['shasum', '-a', '256', '-c', 'CODEX-QUOTA-SHA256SUMS.txt'], cwd=assets, check=True)
info = json.loads((assets / 'CODEX-QUOTA-PROVENANCE.json').read_text())
assert info['kind'] == 'release' and info['workingTreeDirty'] is False
assert info['sourceCommit'] == commit and info['releaseTag'] == tag
assert info['version'] == tag[1:] and info['runtimeVersion'] == 'codex-cli 0.144.1'
dmg = assets / f'codex-quota-{tag}-macos-arm64.dmg'
subprocess.run(['hdiutil', 'verify', str(dmg)], check=True)
mount = plistlib.loads(run('hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(dmg)))
volume = next(pathlib.Path(e['mount-point']) for e in mount['system-entities'] if 'mount-point' in e)
try:
    app = volume / 'Codex Quota.app'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    plist = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert plist['CFBundleIdentifier'] == 'com.jace.codex-quota' and plist['CUSStandalone'] is True
    assert plist['CFBundleShortVersionString'] == tag[1:]
    assert digest(app / 'Contents/MacOS' / plist['CFBundleExecutable']) == info['applicationSignedSha256']
    assert digest(app / 'Contents/Helpers/codex') == info['runtimeSignedSha256']
    snapshot = app / 'Contents/Resources/SOURCE-SNAPSHOT.json'
    assert digest(snapshot) == info['sourceSnapshotSha256']
    for name, expected in json.loads(snapshot.read_text()).items():
        data = run('git', '-C', str(root), 'show', f'{commit}:{name}')
        assert hashlib.sha256(data).hexdigest() == expected, name
    print('Standalone release signature, version, runtime, source and digests verified.')
finally:
    subprocess.run(['hdiutil', 'detach', str(volume)], check=True)
