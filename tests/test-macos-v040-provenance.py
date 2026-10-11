#!/usr/bin/env python3
"""Exercise release provenance acceptance and reject tampered metadata/assets."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

VERIFIER = Path(__file__).resolve().parents[1] / "scripts/verify-macos-v040-provenance.py"


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.git_env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        def git(*args):
            command = ["git"]
            if (args and args[0] != "init"):
                command.extend([f"--git-dir={self.root / '.git'}", f"--work-tree={self.root}"])
            return subprocess.check_output(
                [*command, *args], cwd=self.root, env=self.git_env, stderr=subprocess.DEVNULL
            ).decode().strip()
        git("init")
        git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--allow-empty", "-m", "fixture")
        git("tag", "v0.4.0")
        name = "codex-usage-sidebar-v0.4.0-macos-arm64.dmg"
        self.asset = self.root / name
        self.asset.write_bytes(b"fixture payload")
        self.app = self.root / "Installer.app"
        self.installer = self.app / "Contents/MacOS/CodexUsageSidebarInstaller"
        self.companion = self.app / "Contents/Resources/payload/plugins/codex-usage-sidebar/assets/Codex Usage Sidebar.app/Contents/MacOS/CodexUsageSidebar"
        for executable in (self.installer, self.companion):
            executable.parent.mkdir(parents=True, exist_ok=True)
            executable.write_bytes(b"fixture executable")
        self.commit_file = self.app / "Contents/Resources/InstallerPayloadCommit"
        self.commit_file.write_text(git("rev-parse", "HEAD"))
        self.metadata = {
            "version": "0.4.0", "sourceCommit": git("rev-parse", "HEAD"),
            "payloadCommit": git("rev-parse", "HEAD"), "platform": "macos", "architecture": "arm64",
            "sdk": {"name": "macosx", "version": "26.5"},
            "asset": {"name": name, "sha256": hashlib.sha256(self.asset.read_bytes()).hexdigest()},
            "installer": {"executableSha256": hashlib.sha256(self.installer.read_bytes()).hexdigest()},
            "companion": {"executableSha256": hashlib.sha256(self.companion.read_bytes()).hexdigest()},
        }

    def verify(self):
        (self.root / "MACOS-V040-PROVENANCE.json").write_text(json.dumps(self.metadata))
        return subprocess.run([sys.executable, str(VERIFIER), "v0.4.0", str(self.root), str(self.app)], cwd=self.root,
                              env=self.git_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode

    def test_valid_metadata(self):
        self.assertEqual(self.verify(), 0)

    def test_wrong_source(self):
        self.metadata["sourceCommit"] = "0" * 40
        self.assertNotEqual(self.verify(), 0)

    def test_wrong_payload(self):
        self.metadata["payloadCommit"] = "0" * 40
        self.assertNotEqual(self.verify(), 0)

    def test_wrong_sdk(self):
        self.metadata["sdk"]["version"] = "14.0"
        self.assertNotEqual(self.verify(), 0)

    def test_modified_asset(self):
        self.asset.write_bytes(b"tampered payload")
        self.assertNotEqual(self.verify(), 0)

    def test_relabelled_embedded_source(self):
        self.commit_file.write_text("0" * 40)
        self.assertNotEqual(self.verify(), 0)

    def test_modified_installer(self):
        self.installer.write_bytes(b"different installer")
        self.assertNotEqual(self.verify(), 0)

    def test_modified_companion(self):
        self.companion.write_bytes(b"different companion")
        self.assertNotEqual(self.verify(), 0)


if __name__ == "__main__":
    unittest.main()
