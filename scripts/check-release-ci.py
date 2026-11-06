"""Require successful dual-platform CI for the checked-out release commit."""
import json
import os
import re
import subprocess
import sys

REQUIRED_JOBS = {"macOS build and verification", "Windows standalone build and verification"}


def output(command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout.strip()


def check_release_ci(repository):
    sha = output(["git", "rev-parse", "HEAD"])
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise RuntimeError("Cannot determine the exact release commit")

    def api(endpoint, *arguments):
        return json.loads(output(["gh", "api", "--method", "GET", endpoint, *arguments]))

    evidence = api(f"repos/{repository}/actions/workflows/ci.yml/runs",
                   "-f", f"head_sha={sha}", "-f", "per_page=100")
    runs = evidence["workflow_runs"]
    if evidence["total_count"] != len(runs):
        raise RuntimeError("Incomplete CI run evidence")
    if not runs or any(run["head_sha"] != sha for run in runs):
        raise RuntimeError(f"No exact-commit CI evidence for {sha}")
    # A rerun can update an older run. Its newer result must supersede old successes.
    latest = max(runs, key=lambda run: (run["updated_at"], run["id"]))
    run = api(f"repos/{repository}/actions/runs/{latest['id']}")
    if (run["id"] != latest["id"] or run["head_sha"] != sha
            or run["status"] != "completed" or run["conclusion"] != "success"):
        raise RuntimeError(f"Latest CI run must succeed for {sha}")
    jobs = api(f"repos/{repository}/actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs",
               "-f", "per_page=100")
    if jobs["total_count"] != len(jobs["jobs"]):
        raise RuntimeError("Incomplete CI job evidence")
    for name in REQUIRED_JOBS:
        matches = [job for job in jobs["jobs"] if job["name"] == name]
        if (len(matches) != 1 or matches[0]["status"] != "completed"
                or matches[0]["conclusion"] != "success" or matches[0]["head_sha"] != sha):
            raise RuntimeError(f"Required CI job did not succeed for {sha}: {name}")
    final = api(f"repos/{repository}/actions/runs/{run['id']}")
    if any(final[field] != run[field] for field in
           ("id", "head_sha", "run_attempt", "status", "conclusion")):
        raise RuntimeError("CI run changed during verification")
    print(f"Dual-platform CI passed for {sha} (run {run['id']}, attempt {run['run_attempt']})")


if __name__ == "__main__":
    try:
        check_release_ci(os.environ["GITHUB_REPOSITORY"])
    except (KeyError, ValueError, TypeError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release CI gate failed: {error}", file=sys.stderr)
        sys.exit(1)
