import pathlib
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ReleaseTagRoutingTests(unittest.TestCase):
    def test_governance_accepts_beta_version_files_and_rejects_other_prereleases(self):
        with tempfile.TemporaryDirectory() as temp:
            root=pathlib.Path(temp)
            shutil.copytree(ROOT/'.governance',root/'.governance')
            (root/'scripts').mkdir(); (root/'tests').mkdir()
            for name in ('build-macos-standalone.sh','verify-macos-standalone-release.py'):
                shutil.copy2(ROOT/'scripts'/name,root/'scripts'/name)
            shutil.copy2(ROOT/'tests/test-repository-governance.sh',root/'tests/test-repository-governance.sh')
            shutil.copy2(ROOT/'release-please-config.json',root/'release-please-config.json')
            def run(version):
                (root/'version.txt').write_text(version+'\n')
                (root/'.release-please-manifest.json').write_text(json.dumps({'.':version}))
                return subprocess.run(['bash',str(root/'tests/test-repository-governance.sh')],capture_output=True,text=True).returncode
            self.assertEqual(run('1.8.0-beta.1'),0)
            self.assertNotEqual(run('1.8.0-beta.0'),0)
            self.assertNotEqual(run('1.8.0-rc.1'),0)
    def test_release_please_beta_configuration_starts_with_a_number(self):
        config=json.loads((ROOT/'.governance/release/beta.json').read_text())
        self.assertEqual(config['versioning'],'prerelease')
        self.assertTrue(config['prerelease'])
        self.assertEqual(config['packages']['.']['prerelease-type'],'beta.1')
    def test_github_release_flag_must_match_tag_channel(self):
        script = ROOT / 'scripts/validate-release-channel.py'
        def run(tag, prerelease):
            body = json.dumps({'tagName': tag, 'isPrerelease': prerelease})
            return subprocess.run(['python3', str(script), tag], input=body, text=True, capture_output=True).returncode
        self.assertEqual(run('v1.7.0', False), 0)
        self.assertEqual(run('v1.8.0-beta.1', True), 0)
        self.assertNotEqual(run('v1.8.0-beta.1', False), 0)
        self.assertNotEqual(run('v1.7.0', True), 0)
        self.assertNotEqual(run('v1.8.0-rc.1', True), 0)
    def test_beta_and_stable_tags_route_but_other_prereleases_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / 'scripts').mkdir()
            (root / 'scripts/package-macos-standalone-release.sh').write_text('printf "%s" "$1" > invoked\n')
            adapter = ROOT / '.governance/project/build-release'
            def run(tag):
                (root / 'invoked').unlink(missing_ok=True)
                result = subprocess.run([str(adapter), 'macos-arm64', tag], cwd=root, capture_output=True, text=True)
                return result.returncode, (root / 'invoked').read_text() if (root / 'invoked').exists() else None
            for valid in ('v1.7.0', 'v1.8.0-beta.1', 'v1.8.0-beta.11'):
                code, invoked = run(valid)
                self.assertEqual((code, invoked), (0, valid))
            for invalid in ('v1.8.0-alpha.1', 'v1.8.0-rc.1', 'v1.8.0-beta.0', 'v01.8.0', 'v65535.0.0', 'v1.0.0-beta.2147483648'):
                code, invoked = run(invalid)
                self.assertNotEqual(code, 0, invalid)
                self.assertIsNone(invoked, invalid)

if __name__ == '__main__': unittest.main()
