#!/usr/bin/env python3
"""Exercise synchronization policy using isolated Git repositories and adapters."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

# Git hooks export repository locations. Fixtures must never inherit those paths.
for variable in list(os.environ):
    if variable.startswith("GIT_"):
        os.environ.pop(variable)


class DevelopmentSyncTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="quotabar-sync-")
        self.root = pathlib.Path(self.directory.name)
        subprocess.run(["git", "init", "--quiet", "--initial-branch=codex/fix/sync-test", str(self.root)], check=True)
        shutil.copy2(ROOT / "governance", self.root / "governance")
        policy = self.root / ".governance"
        policy.mkdir()
        shutil.copy2(ROOT / ".governance/policy.defaults.sh", policy / "policy.defaults.sh")
        (policy / "policy.sh").write_text(
            "FAST_CHECK_ADAPTER=.governance/fast\nLOCAL_CHECK_ADAPTER=.governance/local\n"
        )
        for name, variable in [("fast", "SYNC_FAST_STATUS"), ("local", "SYNC_LOCAL_STATUS")]:
            adapter = policy / name
            adapter.write_text(f'#!/bin/sh\necho {name} >> "$SYNC_TRACE"\nexit "${{{variable}:-0}}"\n')
            adapter.chmod(0o755)
        hooks = self.root / ".githooks"
        hooks.mkdir()
        shutil.copy2(ROOT / ".githooks/pre-push", hooks / "pre-push")
        self.trace = self.root / "trace"

    def tearDown(self):
        self.directory.cleanup()

    def run_policy(self, mode="sync", *, draft="0", fast="0", local="0", ci="false", refs=None):
        env = os.environ.copy()
        env.update(QUOTABAR_DRAFT_SYNC=draft, SYNC_FAST_STATUS=fast,
                   SYNC_LOCAL_STATUS=local, SYNC_TRACE=str(self.trace), CI=ci)
        command = ["sh", str(self.root / "governance"), "check", mode]
        if refs is not None:
            command = ["sh", str(self.root / ".githooks/pre-push")]
        return subprocess.run(command, cwd=self.root, env=env, input=refs, text=True, capture_output=True)

    def calls(self):
        return self.trace.read_text().splitlines() if self.trace.exists() else []

    def test_local_runs_both_checks(self):
        result = self.run_policy("local")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["fast", "local"])

    def test_regular_sync_propagates_local_failure(self):
        result = self.run_policy(local="7")
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(self.calls(), ["fast", "local"])

    def test_explicit_draft_sync_reports_failure_and_allows_transfer(self):
        result = self.run_policy(draft="1", local="7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("draft sync", result.stderr.lower())
        self.assertIn("7", result.stderr)
        self.assertEqual(self.calls(), ["fast", "local"])

    def test_draft_sync_never_ignores_fast_check_failure(self):
        result = self.run_policy(draft="1", fast="4")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), ["fast"])

    def test_draft_mode_is_rejected_in_ci(self):
        for ci in ["true", "1", "True"]:
            result = self.run_policy(draft="1", ci=ci)
            self.assertNotEqual(result.returncode, 0, ci)
        self.assertEqual(self.calls(), [])

    def test_draft_mode_is_rejected_on_integration_branches(self):
        for branch in ["main", "codex/prerelease/beta", "release-please--branches--main"]:
            subprocess.run(["git", "symbolic-ref", "HEAD", "refs/heads/" + branch], cwd=self.root, check=True)
            result = self.run_policy(draft="1")
            self.assertNotEqual(result.returncode, 0, branch)
        self.assertEqual(self.calls(), [])

    def test_invalid_draft_flag_is_rejected(self):
        self.assertNotEqual(self.run_policy(draft="yes").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_hook_accepts_only_development_destinations_in_draft_mode(self):
        sha = "a" * 40
        refs = f"refs/heads/codex/fix/sync-test {sha} refs/heads/codex/fix/sync-test {sha}\n"
        result = self.run_policy(draft="1", local="7", refs=refs)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["fast", "local"])

    def test_hook_rejects_push_to_protected_destinations_before_checks(self):
        sha = "a" * 40
        for remote in ["refs/heads/main", "refs/heads/codex/prerelease/beta", "refs/tags/v1.7.0"]:
            refs = f"refs/heads/codex/fix/sync-test {sha} {remote} {sha}\n"
            result = self.run_policy(draft="1", refs=refs)
            self.assertNotEqual(result.returncode, 0, remote)
        self.assertEqual(self.calls(), [])

    def test_hook_checks_every_destination(self):
        sha = "a" * 40
        refs = (f"refs/heads/codex/fix/sync-test {sha} refs/heads/codex/fix/sync-test {sha}\n"
                f"refs/heads/codex/fix/sync-test {sha} refs/heads/main {sha}\n")
        result = self.run_policy(draft="1", refs=refs)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def run_device_adapter(self, operating_system, status="0"):
        project = self.root / ".governance/project"
        project.mkdir()
        shutil.copy2(ROOT / ".governance/project/check-local", project / "check-local")
        full = project / "check-full"
        full.write_text('#!/bin/sh\necho macos >> "$SYNC_TRACE"\n')
        full.chmod(0o755)
        # Functions override uname.exe reliably under Git Bash as well as Unix.
        # A PATH fixture named "uname" can lose to a native Windows executable.
        mock = self.root / "mock-shell.sh"
        mock.write_text(
            f'uname() {{ printf "%s\\n" "{operating_system}"; }}\n'
            'dotnet() { echo "$*" >> "$SYNC_TRACE"; return "$SYNC_DOTNET_STATUS"; }\n'
        )
        env = os.environ.copy()
        env.update(BASH_ENV=str(mock).replace("\\", "/"),
                   SYNC_TRACE=str(self.trace), SYNC_DOTNET_STATUS=status)
        return subprocess.run(["bash", str(project / "check-local")], cwd=self.root,
                              env=env, text=True, capture_output=True)

    def test_windows_device_runs_core_builds_and_native_ui(self):
        result = self.run_device_adapter("MINGW64_NT-10.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [
            "run --project windows/QuotaBar.Core.Tests --configuration Release",
            "build windows/QuotaBar.Windows --configuration Release",
            "build windows/QuotaBar.Setup --configuration Release",
            "run --project windows/QuotaBar.Windows.Tests --configuration Release",
        ])

    def test_windows_device_records_failure_and_attempts_remaining_checks(self):
        result = self.run_device_adapter("MINGW64_NT-10.0", status="9")
        self.assertEqual(result.returncode, 9, result.stderr)
        self.assertEqual(len(self.calls()), 4)

    def test_macos_device_keeps_existing_complete_verification(self):
        result = self.run_device_adapter("Darwin")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["macos"])

    def test_other_device_does_not_claim_native_verification(self):
        result = self.run_device_adapter("Linux")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_complete_checks_report_failure_after_attempting_remaining_checks(self):
        project = self.root / ".governance/project"
        project.mkdir()
        shutil.copy2(ROOT / ".governance/project/check-full", project / "check-full")
        mock = self.root / "mock-full.sh"
        mock.write_text(
            'xcrun() { echo swift >> "$SYNC_TRACE"; return 8; }\n'
            'python3() { echo python >> "$SYNC_TRACE"; }\n'
            'bash() { echo signing >> "$SYNC_TRACE"; }\n'
            'dotnet() { echo dotnet >> "$SYNC_TRACE"; }\n'
        )
        env = os.environ.copy()
        env.update(BASH_ENV=str(mock).replace("\\", "/"), SYNC_TRACE=str(self.trace))
        result = subprocess.run(["bash", str(project / "check-full")], cwd=self.root,
                                env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 8, result.stderr)
        self.assertEqual(self.calls(), ["swift", "python", "python", "signing"] + ["dotnet"] * 4)


if __name__ == "__main__":
    unittest.main()
