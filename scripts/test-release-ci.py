"""Release CI gate regression tests with GitHub CLI boundary fixtures."""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("check-release-ci.py")
SHA = "a" * 40


class ReleaseCITests(unittest.TestCase):
    def check(self, runs=None, detail=None, jobs=None, error=None, run_count=None, final=None):
        spec = importlib.util.spec_from_file_location("release_ci", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        run = {"id": 42, "head_sha": SHA, "status": "completed",
               "conclusion": "success", "updated_at": "2026-11-06T10:00:00Z",
               "run_attempt": 2}
        runs = [run] if runs is None else runs
        jobs = self.jobs() if jobs is None else jobs
        count = len(runs) if run_count is None else run_count
        responses = [
            SHA,
            json.dumps({"total_count": count, "workflow_runs": runs}),
            json.dumps(run if detail is None else detail),
            json.dumps({"total_count": len(jobs), "jobs": jobs}),
            json.dumps(run if final is None else final),
        ]
        commands = []
        def execute(command, **kwargs):
            commands.append(command)
            if error and len(commands) == 2:
                raise error
            return subprocess.CompletedProcess(command, 0, responses.pop(0), "")
        with patch.object(module.subprocess, "run", side_effect=execute):
            module.check_release_ci("owner/repo")
        return commands

    def jobs(self):
        return [{"name": name, "status": "completed", "conclusion": "success",
                 "head_sha": SHA} for name in
                ("macOS build and verification", "Windows standalone build and verification")]

    def test_exact_commit_and_current_attempt_pass(self):
        commands = self.check()
        self.assertIn("head_sha=" + SHA, commands[1])
        self.assertIn("repos/owner/repo/actions/runs/42/attempts/2/jobs", commands[3])

    def test_missing_run_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.check(runs=[])

    def test_wrong_sha_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.check(runs=[{"id": 42, "head_sha": "b" * 40}])

    def test_pending_failed_cancelled_run_is_rejected(self):
        for status, conclusion in [("in_progress", None), ("completed", "failure"),
                                   ("completed", "cancelled")]:
            with self.subTest(conclusion=conclusion), self.assertRaises(RuntimeError):
                self.check(detail={"id": 42, "head_sha": SHA, "status": status,
                                   "conclusion": conclusion, "run_attempt": 2})

    def test_latest_failed_run_blocks_earlier_success(self):
        runs = [{"id": 41, "head_sha": SHA, "updated_at": "2026-11-06T11:00:00Z"},
                {"id": 42, "head_sha": SHA, "updated_at": "2026-11-06T10:00:00Z"}]
        with self.assertRaises(RuntimeError):
            self.check(runs=runs, detail={"id": 41, "head_sha": SHA,
                       "status": "completed", "conclusion": "failure", "run_attempt": 3})

    def test_missing_skipped_failed_or_pending_platform_is_rejected(self):
        cases = [self.jobs()[:1]]
        for status, conclusion in [("completed", "skipped"), ("completed", "failure"),
                                   ("in_progress", None)]:
            jobs = self.jobs()
            jobs[1].update(status=status, conclusion=conclusion)
            cases.append(jobs)
        for jobs in cases:
            with self.subTest(jobs=jobs), self.assertRaises(RuntimeError):
                self.check(jobs=jobs)

    def test_truncated_run_evidence_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.check(run_count=101)

    def test_rerun_started_during_job_inspection_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.check(final={"id": 42, "head_sha": SHA, "status": "in_progress",
                              "conclusion": None, "run_attempt": 3})

    def test_api_error_is_rejected(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.check(error=subprocess.CalledProcessError(1, "gh"))

    def test_changed_detail_commit_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.check(detail={"id": 42, "head_sha": "b" * 40,
                       "status": "completed", "conclusion": "success", "run_attempt": 2})


if __name__ == "__main__":
    unittest.main()
