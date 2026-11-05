import importlib.util
import json
import hashlib
import pathlib
import unittest
import sys
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('update_feed', pathlib.Path(__file__).with_name('generate-update-feed.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class FeedTests(unittest.TestCase):
    def release(self, version, platform, draft=False, prerelease=False):
        tag='v'+version
        names=module.asset_names(platform, version)
        return {'tag_name':tag,'draft':draft,'prerelease':prerelease,'published_at':'2026-10-13T00:00:00Z','assets':[{'name':n,'size':100,'browser_download_url':f'https://github.com/JaceHwang/QuotaBar/releases/download/{tag}/{n}'} for n in names]}
    def proof(self, release, platform):
        return {'kind':'release','version':release['tag_name'][1:],'releaseTag':release['tag_name'],'workingTreeDirty':False,'nativeMacOSStartupExit':True,'sourceCommit':'b'*40}
    def generate(self, releases, load_proof):
        return module.generate(releases,load_proof,lambda release:'b'*40)
    def test_beta_channel_is_verified_separate_and_selects_each_platform(self):
        releases=[self.release('1.7.0','windows-x64'), self.release('1.7.0','macos-arm64'),
                  self.release('1.8.0-beta.2','windows-x64',prerelease=True),
                  self.release('1.8.0-beta.11','windows-x64',prerelease=True),
                  self.release('1.8.0-beta.3','macos-arm64',prerelease=True),
                  self.release('1.9.0-beta.1','macos-arm64',draft=True,prerelease=True),
                  self.release('2.0.0-beta.1','windows-x64',prerelease=False),
                  self.release('3.0.0','windows-x64',prerelease=True)]
        feed=self.generate(releases,self.proof)
        self.assertEqual(feed['stable']['windows-x64']['version'],'1.7.0')
        self.assertEqual(feed['beta']['windows-x64']['version'],'1.8.0-beta.11')
        self.assertEqual(feed['beta']['macos-arm64']['version'],'1.8.0-beta.3')
        bad=self.release('1.8.0-beta.12','windows-x64',prerelease=True); bad['assets'].pop()
        self.assertEqual(self.generate(releases+[bad],self.proof)['beta']['windows-x64']['version'],'1.8.0-beta.11')
    def test_renamed_repository_assets_are_accepted(self):
        release=self.release('1.1.0','windows-x64')
        for asset in release['assets']:
            asset['browser_download_url']=asset['browser_download_url'].replace('/codex-usage-sidebar/','/QuotaBar/')
        self.assertEqual(self.generate([release],self.proof)['stable'].get('windows-x64',{}).get('version'),'1.1.0')
        release['assets'][0]['browser_download_url']=release['assets'][0]['browser_download_url'].replace('/QuotaBar/','/QuotaBar-evil/')
        self.assertEqual(self.generate([release],self.proof)['stable'],{})
    def test_release_notes_are_embedded_as_plain_text(self):
        release=self.release('0.7.0','windows-x64')
        release['body']='## Changes\n- Fix quota refresh\n- Add update reminders'
        entry=self.generate([release],self.proof)['stable']['windows-x64']
        self.assertEqual(entry.get('releaseNotes'),'Changes\n• Fix quota refresh\n• Add update reminders')
        self.assertEqual(entry.get('summary'),'Fix quota refresh · Add update reminders')
    def test_empty_markup_and_long_notes(self):
        self.assertEqual(module.release_text(None),('', ''))
        summary, notes=module.release_text('## Changes\n- **Fix** [refresh](https://example.com) <b>now</b>')
        self.assertEqual(summary,'Fix refresh now')
        self.assertNotIn('https://', notes)
        summary, notes=module.release_text('- '+('中'*17000))
        self.assertEqual(len(summary),240)
        self.assertEqual(len(notes),16000)
    def test_withdrawn_macos_release_does_not_hide_windows(self):
        releases=[self.release('1.0.0','macos-arm64'),self.release('1.0.0','windows-x64'),self.release('0.6.0','macos-arm64')]
        def proof(release,platform):
            value=self.proof(release,platform)
            if platform=='macos-arm64' and release['tag_name']=='v1.0.0': value['nativeMacOSStartupExit']=False
            return value
        feed=self.generate(releases,proof)['stable']
        self.assertEqual(feed['macos-arm64']['version'],'0.6.0')
        self.assertEqual(feed['windows-x64']['version'],'1.0.0')
    def test_missing_native_macos_proof_omits_only_macos(self):
        releases=[self.release('1.0.0','macos-arm64'),self.release('1.0.0','windows-x64')]
        def proof(release,platform):
            value=self.proof(release,platform); value.pop('nativeMacOSStartupExit',None); return value
        feed=self.generate(releases,proof)['stable']
        self.assertNotIn('macos-arm64',feed)
        self.assertEqual(feed['windows-x64']['version'],'1.0.0')
    def test_main_deploys_a_windows_only_feed_successfully(self):
        releases=[self.release('1.0.0','macos-arm64'),self.release('1.0.0','windows-x64')]
        def proof(release,platform):
            value=self.proof(release,platform); value.pop('nativeMacOSStartupExit',None); return value
        with tempfile.TemporaryDirectory() as temporary:
            output=pathlib.Path(temporary)/'updates.json'
            with patch.object(sys,'argv',['generate-update-feed.py','--output',str(output)]), patch.object(module.subprocess,'check_output',return_value=json.dumps([releases])), patch.object(module,'load_proof',side_effect=proof), patch.object(module,'resolve_tag_commit',return_value='b'*40):
                module.main()
            self.assertEqual(list(json.loads(output.read_text())['stable']),['windows-x64'])
    def test_platform_skew_numeric_order_and_drafts(self):
        releases=[self.release('0.7.0','windows-x64'),self.release('0.6.0','macos-arm64'),self.release('0.10.0','windows-x64',draft=True),self.release('0.9.0','windows-x64')]
        result=self.generate(releases,self.proof)
        self.assertEqual(result['stable']['macos-arm64']['version'],'0.6.0')
        self.assertEqual(result['stable']['windows-x64']['version'],'0.9.0')
        releases.append(self.release('0.10.0','windows-x64'))
        self.assertEqual(self.generate(releases,self.proof)['stable']['windows-x64']['version'],'0.10.0')
    def test_missing_assets_and_bad_provenance_do_not_advance(self):
        good=self.release('0.6.0','macos-arm64'); bad=self.release('0.7.0','macos-arm64'); bad['assets'].pop()
        self.assertEqual(self.generate([bad,good],self.proof)['stable']['macos-arm64']['version'],'0.6.0')
        def candidate(release, platform):
            proof=self.proof(release,platform);proof['kind']='local-development-candidate';return proof
        with self.assertRaises(ValueError): self.generate([good],candidate)
    def test_complete_newer_release_with_mismatched_provenance_aborts_feed(self):
        old=self.release('1.8.0-beta.3','windows-x64',prerelease=True)
        new=self.release('1.8.0-beta.4','windows-x64',prerelease=True)
        def wrong(release,platform):
            result=self.proof(release,platform)
            if release['tag_name']=='v1.8.0-beta.4': result['version']='1.8.0-beta.3'
            return result
        with self.assertRaises(ValueError): self.generate([old,new],wrong)
    def test_source_commit_must_match_the_exact_release_tag(self):
        release=self.release('1.8.0-beta.1','windows-x64',prerelease=True)
        with self.assertRaises(ValueError):
            module.generate([release],self.proof,lambda release:'a'*40)
    def test_resolve_annotated_tag_to_commit(self):
        release=self.release('1.8.0-beta.1','windows-x64',prerelease=True)
        first=json.dumps({'object':{'type':'tag','sha':'a'*40}})
        second=json.dumps({'object':{'type':'commit','sha':'b'*40}})
        with patch.object(module.subprocess,'check_output',side_effect=[first,second]) as gh:
            self.assertEqual(module.resolve_tag_commit(release),'b'*40)
        self.assertEqual(gh.call_count,2)
    def test_metadata_checksums_and_native_verification_are_required(self):
        release = self.release('0.7.0', 'windows-x64')
        release['assets'][0]['digest']='sha256:'+'b'*64
        commit = 'a' * 40
        proof = self.proof(release, 'windows-x64'); proof['sourceCommit'] = commit
        verification = {'schema': 1, 'tag': 'v0.7.0', 'sourceCommit': commit, 'archiveSHA256': 'b' * 64, 'nativeWindowsStartupExit': True, 'nativeWindowsInstallUpgradeRollbackUninstall': True}
        def assets():
            docs = {'QUOTABAR-WINDOWS-PROVENANCE.json': json.dumps(proof).encode(), 'QUOTABAR-WINDOWS-VERIFICATION.json': json.dumps(verification).encode()}
            sums = 'b' * 64 + '  QuotaBar-0.7.0-windows-x64.zip\n'
            sums += ''.join(hashlib.sha256(data).hexdigest() + '  ' + name + '\n' for name, data in docs.items())
            docs['QUOTABAR-WINDOWS-SHA256SUMS.txt'] = sums.encode()
            return docs
        original = module.read_asset
        try:
            docs = assets(); module.read_asset = lambda release, name: docs[name]
            self.assertEqual(module.load_proof(release, 'windows-x64')['sourceCommit'], commit)
            release['assets'][0]['digest']='sha256:'+'c'*64
            with self.assertRaises(ValueError): module.load_proof(release, 'windows-x64')
            release['assets'][0]['digest']='sha256:'+'b'*64
            verification['nativeWindowsStartupExit'] = False; docs = assets()
            with self.assertRaises(ValueError): module.load_proof(release, 'windows-x64')
            verification['nativeWindowsStartupExit'] = True; verification['sourceCommit'] = 'c' * 40; docs = assets()
            with self.assertRaises(ValueError): module.load_proof(release, 'windows-x64')
            docs['QUOTABAR-WINDOWS-PROVENANCE.json'] += b' '
            with self.assertRaises(ValueError): module.load_proof(release, 'windows-x64')
        finally: module.read_asset = original
    def test_transport_failure_preserves_existing_feed_by_failing_build(self):
        def failure(release, platform): raise OSError('network unavailable')
        with self.assertRaises(OSError): self.generate([self.release('0.7.0','windows-x64')],failure)

if __name__=='__main__': unittest.main()
