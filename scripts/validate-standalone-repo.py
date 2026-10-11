#!/usr/bin/env python3
"""Validate the standalone layout, runtime boundary and local documentation links."""
import json,pathlib,re,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
for name in ['native/Package.swift','native/Sources/CodexQuota/main.swift','scripts/build-macos-standalone.sh','scripts/install-macos-standalone.py','docs/PROJECT_PROGRESS-standalone-app.md','docs/MACOS_STANDALONE.zh-CN.md','docs/validation/macos-standalone.md']:
    assert (root/name).is_file(),name
assert not (root/'plugins').exists(), 'Legacy plugin tree must not remain in the standalone workspace'
assert not (root/'.agents/plugins').exists(), 'Legacy marketplace entry must not remain'
package=(root/'native/Package.swift').read_text()
assert 'CodexQuota' in package and 'QuotaCore' in package and 'InstallerCore' not in package
for p in (root/'native/Sources').rglob('*.swift'):
    text=p.read_text()
    for forbidden in ['AXUIElement', 'AXIsProcessTrusted', 'CGWindowListCopyWindowInfo', 'HostDiscovery', 'RuntimeCoordinator', 'CompanionRuntimeConfiguration']:
        assert forbidden not in text,(str(p.relative_to(root)),forbidden)
for p in [*root.glob('*.json'),*(root/'.governance').rglob('*.json'),*(root/'contracts').rglob('*.json')]:
    json.loads(p.read_text())
for p in [*root.glob('*.md'),*(root/'docs').rglob('*.md')]:
    text=p.read_text()
    if p.name!='AGENTS.md':
        assert not re.search(r'/Users/[^/\s]+/',text),str(p)
        assert not re.search(r'\bsk-[A-Za-z0-9]{20,}\b',text),str(p)
    for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)',text):
        if '://' in target or target.startswith('#'):continue
        target=target.split('#',1)[0].split(' "',1)[0]
        if not target:continue
        assert (p.parent/target).exists(),(str(p.relative_to(root)),target)
for p in (root/'scripts').glob('*.sh'):
    subprocess.run(['bash','-n',str(p)],check=True)
for p in (root/'.governance/project').iterdir():
    subprocess.run(['sh','-n',str(p)],check=True)
print('Standalone layout, host isolation, JSON, privacy, links and shell syntax passed')
