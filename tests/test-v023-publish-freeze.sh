#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python="${PYTHON:-python3}"
ci="$repo_root/.github/workflows/ci.yml"
publisher="$repo_root/.github/workflows/publish-installer.yml"
builder="$repo_root/scripts/build-installer.sh"
frozen_commit="a72b4636ddf99fa4c1d4660b3e281376be361711"

"$python" - "$ci" "$publisher" "$builder" "$frozen_commit" <<'PY'
import sys
from pathlib import Path

ci = Path(sys.argv[1]).read_text(encoding="utf-8")
publisher = Path(sys.argv[2]).read_text(encoding="utf-8")
builder = Path(sys.argv[3]).read_text(encoding="utf-8")
commit = sys.argv[4]

binding = f"FROZEN_V023_INSTALLER_SOURCE_COMMIT: {commit}"
if binding not in ci or binding not in publisher:
    raise SystemExit("stable v0.2.3 workflows are not bound to the published source commit")

if ci.count("if: github.sha == env.FROZEN_V023_INSTALLER_SOURCE_COMMIT") < 3:
    raise SystemExit("future CI commits can still upload stable v0.2.3 artifacts")

installer_payload_binding = "CUS_INSTALLER_PAYLOAD_REF: ${{ env.FROZEN_V023_INSTALLER_SOURCE_COMMIT }}"
if installer_payload_binding not in ci:
    raise SystemExit("stable v0.2.3 installer test is not pinned to the published payload commit")

payload_manifest_lookup = '"$payload_commit:plugins/codex-usage-sidebar/.codex-plugin/plugin.json"'
if payload_manifest_lookup not in builder:
    raise SystemExit("stable v0.2.3 installer builder reads the current manifest instead of the payload manifest")

required_publisher_guards = (
    "test \"$(jq -r '.head_sha' <<<\"$run\")\" = \"$FROZEN_V023_INSTALLER_SOURCE_COMMIT\"",
    "--pattern 'INSTALLER-PROVENANCE.json'",
    "test \"$(jq -r '.installerSourceCommit' \"$RUNNER_TEMP/release/INSTALLER-PROVENANCE.json\")\" = \"$FROZEN_V023_INSTALLER_SOURCE_COMMIT\"",
)
for guard in required_publisher_guards:
    if guard not in publisher:
        raise SystemExit(f"stable v0.2.3 publisher is missing freeze guard: {guard}")

promoted_payload_restore = (
    "git restore --source=HEAD -- "
    "'plugins/codex-usage-sidebar/assets/Codex Usage Sidebar.app' "
    "'plugins/codex-usage-sidebar/assets/PROVENANCE.json'"
)
if promoted_payload_restore not in ci:
    raise SystemExit(
        "main release packaging must restore both the promoted companion and its provenance"
    )

print("PASS: macOS v0.2.3 CI artifacts and publisher are frozen to the published source")
PY
