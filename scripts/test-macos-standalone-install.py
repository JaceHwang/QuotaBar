import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import shutil
import sys
import plistlib
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('installer', Path(__file__).with_name('install-macos-standalone.py'))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class PluginMigrationTests(unittest.TestCase):
    def test_disable_and_restore_only_target_flag(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.toml'
            original = '[other]\nenabled = true\n[plugins."codex-usage-sidebar@codex-usage-sidebar"]\nenabled = true # retain\n[plugins."other"]\nenabled = true\n'
            path.write_text(original)
            previous = installer.set_plugin_enabled(path, False)
            self.assertTrue(previous)
            self.assertIn('enabled = false # retain', path.read_text())
            installer.set_plugin_enabled(path, previous)
            self.assertEqual(path.read_text(), original)

    def test_indented_next_table_cannot_supply_missing_flag(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.toml'
            original = '[plugins."codex-usage-sidebar@codex-usage-sidebar"]\nname = "legacy"\n  [plugins."other"]\nenabled = true\n'
            path.write_text(original)
            with self.assertRaises(RuntimeError):
                installer.set_plugin_enabled(path, False)
            self.assertEqual(path.read_text(), original)

    def test_missing_plugin_does_not_create_config(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.toml'
            self.assertIsNone(installer.set_plugin_enabled(path, False))
            self.assertFalse(path.exists())

class IsolatedGlobalInstallTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name) / 'home'
        self.home.mkdir()
        self.global_app = Path(self.directory.name) / 'Applications/QuotaBar.app'
        self.patcher = patch.object(installer, 'GLOBAL_APPLICATION', self.global_app, create=True)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_old_candidate_is_rejected_before_installation(self):
        candidate = self.home / 'candidate.app'
        (candidate / 'Contents').mkdir(parents=True)
        (candidate / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.jace.codex-quota', 'CUSStandalone': True
        }))
        with patch.object(installer, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'does not support installation'):
                installer.verify(candidate, require_global=True)
            run.assert_not_called()

    def test_global_target_is_preferred_over_user_copy(self):
        user = self.home / 'Applications/QuotaBar.app'
        user.mkdir(parents=True)
        self.global_app.mkdir(parents=True)
        self.assertEqual(installer.active_application(self.home), self.global_app)

    def test_install_migrates_user_copy_and_preserves_global_backup(self):
        user = self.home / 'Applications/QuotaBar.app'
        user.mkdir(parents=True)
        (user / 'user-version').write_text('user')
        self.global_app.mkdir(parents=True)
        (self.global_app / 'global-version').write_text('global')
        candidate = self.home / 'candidate.app'
        candidate.mkdir()
        (candidate / 'new-version').write_text('new')
        def run(*args):
            if args[0] == 'ditto':
                shutil.copytree(args[1], args[2])
        with patch.object(installer.Path, 'home', return_value=self.home), patch.object(installer, 'verify'), patch.object(installer, 'stop'), patch.object(installer, 'startup_enabled', return_value=False), patch.object(installer, 'run', side_effect=run), patch.object(sys, 'argv', ['installer', 'install', '--candidate', str(candidate)]):
            installer.main()
        self.assertTrue((self.global_app / 'new-version').exists())
        self.assertFalse(user.exists())
        backups = self.home / 'Library/Application Support/CodexUsageSidebar/.StandaloneBackups'
        self.assertEqual(len(list(backups.glob('*.app'))), 2)

    def test_failed_migration_restores_both_installed_copies(self):
        user = self.home / 'Applications/QuotaBar.app'
        for path, name in [(user, 'user'), (self.global_app, 'global')]:
            path.mkdir(parents=True)
            (path / 'version').write_text(name)
        candidate = self.home / 'candidate.app'
        candidate.mkdir()
        failed = False
        def run(*args):
            nonlocal failed
            if args[0] == 'ditto':
                shutil.copytree(args[1], args[2])
            elif args[0] == 'open' and not failed:
                failed = True
                raise RuntimeError('activation failed')
        with patch.object(installer.Path, 'home', return_value=self.home), patch.object(installer, 'verify'), patch.object(installer, 'stop'), patch.object(installer, 'startup_enabled', return_value=False), patch.object(installer, 'run', side_effect=run), patch.object(sys, 'argv', ['installer', 'install', '--candidate', str(candidate)]):
            with self.assertRaisesRegex(RuntimeError, 'activation failed'):
                installer.main()
        self.assertEqual((user / 'version').read_text(), 'user')
        self.assertEqual((self.global_app / 'version').read_text(), 'global')

class InstallTransactionTests(unittest.TestCase):
    def test_interrupted_application_move_recovers_previous(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / 'data'
            backups = root / '.StandaloneBackups'
            backups.mkdir(parents=True)
            previous = backups / 'previous.app'
            previous.mkdir()
            (previous / 'old').write_text('previous')
            target = home / 'Applications/Codex Quota.app'
            target.parent.mkdir()
            info = {'target': str(target), 'previous': str(previous), 'oldMarker': 'existing marker', 'oldRecord': {'previous': None}, 'legacy': {}}
            with patch.object(installer, 'run'), patch.object(installer, 'stop'):
                installer.recover_install(home, info, root / 'standalone-mode', root / 'standalone-install.json', backups, reopen=False)
            self.assertTrue((target / 'old').exists())
            self.assertEqual((root / 'standalone-mode').read_text(), 'existing marker')

    def test_interrupted_rollback_retains_both_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / 'data'
            backups = root / '.StandaloneBackups'
            backups.mkdir(parents=True)
            previous = backups / 'current.app'
            previous.mkdir()
            (previous / 'current').write_text('current')
            target = home / 'Applications/Codex Quota.app'
            target.mkdir(parents=True)
            (target / 'older').write_text('older')
            original_previous = backups / 'older.app'
            info = {'target': str(target), 'previous': str(previous), 'replacementSource': str(original_previous), 'oldRecord': {'previous': str(original_previous)}, 'oldMarker': 'standalone', 'legacy': {}}
            with patch.object(installer, 'run'), patch.object(installer, 'stop'):
                installer.recover_install(home, info, root / 'standalone-mode', root / 'standalone-install.json', backups, reopen=False)
            self.assertTrue((target / 'current').exists())
            self.assertTrue((original_previous / 'older').exists())

    def test_running_legacy_service_aborts_before_touching_plist(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'agent.plist'
            path.write_bytes(plistlib.dumps({'ProgramArguments': ['/legacy.app/Contents/MacOS/legacy']}))
            with patch.object(installer.subprocess, 'run', return_value=SimpleNamespace(returncode=0)), patch.object(installer, 'stop') as stop:
                with self.assertRaisesRegex(RuntimeError, 'still running'):
                    installer.suspend_legacy(path)
                stop.assert_not_called()
            self.assertTrue(path.exists())

    def test_failed_activation_restores_application_and_legacy(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            target = home / 'Applications/Codex Quota.app'
            target.mkdir(parents=True)
            (target / 'old').write_text('previous')
            source = home / 'candidate.app'
            source.mkdir()
            (source / 'new').write_text('candidate')
            config = home / '.codex/config.toml'
            config.parent.mkdir()
            config.write_text('[plugins."codex-usage-sidebar@codex-usage-sidebar"]\nenabled = true\n')
            plist = home / 'Library/LaunchAgents/com.jace.codex-usage-sidebar.plist'
            plist.parent.mkdir(parents=True)
            plist.write_bytes(plistlib.dumps({'ProgramArguments': ['/legacy.app/Contents/MacOS/legacy']}))
            failed = False
            def run(*args):
                nonlocal failed
                if args[0] == 'ditto':
                    shutil.copytree(args[1], args[2]) if Path(args[1]).is_dir() else shutil.copy2(args[1], args[2])
                elif args[0] == 'open' and not failed:
                    failed = True
                    raise RuntimeError('injected activation failure')
            with patch.object(installer, 'GLOBAL_APPLICATION', home / 'GlobalApplications/QuotaBar.app', create=True), patch.object(installer.Path, 'home', return_value=home), patch.object(installer, 'verify'), patch.object(installer, 'stop'), patch.object(installer, 'run', side_effect=run), patch.object(installer.subprocess, 'run', return_value=SimpleNamespace(returncode=1)), patch.object(sys, 'argv', ['installer', 'install', '--candidate', str(source)]):
                with self.assertRaisesRegex(RuntimeError, 'injected activation failure'):
                    installer.main()
            self.assertTrue((target / 'old').exists())
            self.assertTrue(plist.exists())
            self.assertIn('enabled = true', config.read_text())
            self.assertFalse((home / 'Library/Application Support/CodexUsageSidebar/standalone-mode').exists())

class BrandingMigrationTests(unittest.TestCase):
    def test_active_application_recognizes_previous_bundle_name(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            old = home / 'Applications/Codex Quota.app'
            old.mkdir(parents=True)
            with patch.object(installer, 'GLOBAL_APPLICATION', home / 'GlobalApplications/QuotaBar.app', create=True):
                self.assertEqual(installer.active_application(home), old)
            new = home / 'Applications/QuotaBar.app'
            old.rename(new)
            with patch.object(installer, 'GLOBAL_APPLICATION', home / 'GlobalApplications/QuotaBar.app', create=True):
                self.assertEqual(installer.active_application(home), new)

    def test_uninstall_after_interrupted_rename_uses_recovered_path(self):
        import json
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory); root = home/'Library/Application Support/CodexUsageSidebar'; backups = root/'.StandaloneBackups'; backups.mkdir(parents=True)
            old = home/'Applications/Codex Quota.app'; new = home/'Applications/QuotaBar.app'; new.mkdir(parents=True)
            previous = backups/'previous.app'; previous.mkdir()
            info = {'target':str(new),'originalTarget':str(old),'previous':str(previous),'oldRecord':{'target':str(old)},'oldMarker':'standalone','legacy':{}}
            (root/'standalone-transaction.json').write_text(json.dumps(info))
            with patch.object(installer,'GLOBAL_APPLICATION',home/'GlobalApplications/QuotaBar.app',create=True), patch.object(installer.Path,'home',return_value=home), patch.object(installer,'run'), patch.object(installer,'stop'), patch.object(installer,'application_executable',return_value=Path('/fake/executable')), patch.object(sys,'argv',['installer','uninstall']):
                installer.main()
            self.assertFalse(old.exists()); self.assertFalse(new.exists())
            self.assertFalse((root/'standalone-mode').exists())

    def test_failed_branding_upgrade_restores_original_path(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory); root = home / 'data'; backups = root / 'backups'; backups.mkdir(parents=True)
            old = home / 'Applications/Codex Quota.app'; old.parent.mkdir()
            previous = backups / 'previous.app'; previous.mkdir(); (previous / 'old').write_text('old')
            new = home / 'Applications/QuotaBar.app'; new.mkdir()
            info = {'target': str(new), 'originalTarget': str(old), 'previous': str(previous), 'oldRecord': {'target':str(old)}, 'oldMarker':None, 'legacy':{}}
            with patch.object(installer,'run'), patch.object(installer,'stop'):
                installer.recover_install(home, info, root/'marker', root/'record', backups, reopen=False)
            self.assertTrue((old/'old').exists()); self.assertFalse(new.exists())

if __name__ == '__main__':
    unittest.main()
