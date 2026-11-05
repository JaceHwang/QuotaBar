#!/usr/bin/env python3
"""Build separate stable and beta Pages entries from verified public releases."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import time
import urllib.error
import urllib.request

REPO = 'JaceHwang/QuotaBar'
PLATFORMS = ('macos-arm64', 'windows-x64')

def asset_names(platform, version):
    if platform == 'macos-arm64':
        return [f'codex-quota-v{version}-macos-arm64.dmg', 'CODEX-QUOTA-PROVENANCE.json', 'CODEX-QUOTA-SHA256SUMS.txt', 'CODEX-QUOTA-INSTALL.zh-CN.md', 'install-macos-standalone.py']
    return [f'QuotaBar-{version}-windows-x64.zip', 'QUOTABAR-WINDOWS-PROVENANCE.json', 'QUOTABAR-WINDOWS-SHA256SUMS.txt', 'QUOTABAR-WINDOWS-VERIFICATION.json', 'QUOTABAR-WINDOWS-INSTALL.zh-CN.md']

def release_text(body):
    # Render release prose as inert plain text; no remote HTML or executable content.
    body = body if isinstance(body, str) else ''
    body = re.sub(r'<[^>]*>', '', body)
    body = re.sub(r'!?\[([^]]*)\]\([^)]*\)', r'\1', body)
    lines = []
    bullets = []
    for line in body.splitlines():
        line = re.sub(r'^\s*#{1,6}\s*', '', line).strip()
        line = line.replace('**', '').replace('`', '')
        if re.match(r'^[-*+]\s+', line):
            line = re.sub(r'^[-*+]\s+', '', line)
            bullets.append(line)
            line = '• ' + line
        if line: lines.append(line)
    notes = '\n'.join(lines)[:16000]
    summary = ' · '.join(bullets[:3] or lines[:1])[:240]
    return summary, notes

def generate(releases, load_proof, resolve_tag):
    feed = {'schemaVersion': 1, 'stable': {}, 'beta': {}}
    candidates = []
    commits = {}
    for release in releases:
        tag = release.get('tag_name', '')
        if release.get('draft') or not release.get('published_at'):
            continue
        match = re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-beta\.([1-9][0-9]*))?', tag)
        if not match or len(tag) > 129:
            continue
        numbers = tuple(map(int, match.groups()[:3])); beta_number = int(match.group(4)) if match.group(4) else None
        if any(n > 65534 for n in numbers) or (beta_number is not None and beta_number > 2147483647):
            continue
        channel = 'beta' if beta_number is not None else 'stable'
        if release.get('prerelease') is not (channel == 'beta'):
            continue
        candidates.append((numbers + ((0, beta_number) if beta_number is not None else (1, 0)), channel, release))
    for _, channel, release in sorted(candidates, key=lambda item: item[0], reverse=True):
        tag = release['tag_name']; version = tag[1:]
        assets = {a['name']: a for a in release.get('assets', [])}
        for platform in PLATFORMS:
            if platform in feed[channel]:
                continue
            names = asset_names(platform, version)
            if not all(n in assets and assets[n].get('size', 0) > 0 and assets[n].get('browser_download_url') == f'https://github.com/{REPO}/releases/download/{tag}/{n}' for n in names):
                continue
            proof = load_proof(release, platform)
            if not (proof.get('kind') == 'release' and proof.get('version') == version and proof.get('releaseTag') == tag and proof.get('workingTreeDirty') is False):
                raise ValueError(f'Provenance does not match {tag} for {platform}; retain the deployed feed')
            if tag not in commits:
                commits[tag] = resolve_tag(release)
            if proof.get('sourceCommit') != commits[tag]:
                raise ValueError(f'Tag commit does not match provenance for {tag}; retain the deployed feed')
            # Static signature/hash checks do not prove the packaged App can launch.
            # Older macOS assets without this proof are no longer offered as updates.
            if platform == 'macos-arm64' and proof.get('nativeMacOSStartupExit') is not True:
                continue
            summary, notes = release_text(release.get('body'))
            feed[channel][platform] = {
                'summary': summary, 'releaseNotes': notes,
                'version': version, 'minOS': '14.0' if platform == 'macos-arm64' else '10.0.22000',
                'releaseNotesURL': f'https://github.com/{REPO}/releases/tag/{tag}',
                'downloadURL': assets[names[0]]['browser_download_url'], 'publishedAt': release['published_at']
            }
    return feed

def resolve_tag_commit(release):
    tag = release.get('tag_name', '')
    if not re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-beta\.[1-9][0-9]*)?', tag):
        raise ValueError('Invalid release tag')
    endpoint = f'repos/{REPO}/git/ref/tags/{tag}'
    for _ in range(4):
        record = json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))
        obj = record.get('object', {})
        sha = obj.get('sha', '')
        if not isinstance(sha, str) or not re.fullmatch(r'[a-f0-9]{40}', sha):
            raise ValueError('Invalid tag object SHA')
        if obj.get('type') == 'commit': return sha
        if obj.get('type') != 'tag': raise ValueError('Tag does not point to a commit')
        endpoint = f'repos/{REPO}/git/tags/{sha}'
    raise ValueError('Annotated tag chain is too deep')

def load_proof(release, platform):
    name = asset_names(platform, release['tag_name'][1:])[1]
    data = read_asset(release, name)
    proof = json.loads(data)
    checksum_name = asset_names(platform, release['tag_name'][1:])[2]
    checksums = read_asset(release, checksum_name).decode('utf-8')
    binary = asset_names(platform, release['tag_name'][1:])[0]
    digest = None
    expected = {}
    for line in checksums.splitlines():
        fields = line.split()
        if len(fields) == 2 and re.fullmatch(r'[a-fA-F0-9]{64}', fields[0]):
            expected[fields[1].lstrip('*')] = fields[0].lower()
    digest = expected.get(binary)
    if digest is None: raise ValueError('Release archive checksum is missing')
    archive = next(asset for asset in release['assets'] if asset['name'] == binary)
    if archive.get('digest') != 'sha256:' + digest:
        raise ValueError('GitHub archive digest does not match the verified checksum')
    if expected.get(name) != hashlib.sha256(data).hexdigest(): raise ValueError('Provenance checksum mismatch')
    if platform == 'windows-x64':
        verification_data = read_asset(release, 'QUOTABAR-WINDOWS-VERIFICATION.json')
        if expected.get('QUOTABAR-WINDOWS-VERIFICATION.json') != hashlib.sha256(verification_data).hexdigest(): raise ValueError('Verification checksum mismatch')
        verification = json.loads(verification_data)
        if not (verification.get('schema') == 1 and verification.get('tag') == release['tag_name'] and verification.get('sourceCommit') == proof.get('sourceCommit') and verification.get('archiveSHA256') == digest and verification.get('nativeWindowsStartupExit') is True and verification.get('nativeWindowsInstallUpgradeRollbackUninstall') is True):
            raise ValueError('Windows native verification does not match release provenance/checksum')
    if not re.fullmatch(r'[a-f0-9]{40}', proof.get('sourceCommit', '')):
        raise ValueError('Release provenance has no source commit')
    return proof

def read_asset(release, name):
    asset = next(a for a in release['assets'] if a['name'] == name)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(asset['browser_download_url'], headers={'User-Agent': 'QuotaBar-feed-generator'}), timeout=20) as response:
                data = response.read(262145)
            break
        except (urllib.error.URLError, OSError):
            if attempt == 2: raise
            time.sleep(attempt + 1)
    if len(data) > 262144: raise ValueError('Release metadata too large')
    return data

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    # Pagination prevents a Windows-only latest release from hiding an older macOS release.
    raw = subprocess.check_output(['gh', 'api', '--paginate', '--slurp', f'repos/{REPO}/releases?per_page=100'], text=True)
    releases = [release for page in json.loads(raw) for release in page]
    feed = generate(releases, load_proof, resolve_tag_commit)
    if 'windows-x64' not in feed['stable']:
        raise ValueError('Verified Windows release is missing; keep the previously deployed feed')
    # macOS may be intentionally omitted until a runtime-verified release exists.
    # Clients already treat a missing platform entry as no available update.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix('.tmp')
    temporary.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + '\n')
    temporary.replace(args.output)
    print('Built update feed: ' + ', '.join(c + '/' + p + '=' + feed[c][p]['version'] for c in ('stable', 'beta') for p in PLATFORMS if p in feed[c]))

if __name__ == '__main__':
    main()
