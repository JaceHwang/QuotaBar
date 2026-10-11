#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python="${PYTHON:-python3}"
hooks="$plugin_root/hooks/hooks.json"
control="$plugin_root/scripts/sidebar-control-windows.ps1"
version_manifest="$plugin_root/../../.release-please-manifest.json"
windows_props="$plugin_root/windows/Directory.Build.props"

"$python" - "$hooks" <<'PY'
import json
import sys
from pathlib import Path

document = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
hook = document["hooks"]["SessionStart"][0]["hooks"][0]
command = hook.get("commandWindows", "")
assert "powershell.exe" in command
assert "sidebar-control-windows.ps1" in command
assert "${PLUGIN_ROOT}" in command
assert "${PLUGIN_DATA}" in command
PY

[[ -f "$control" ]]
"$python" - "$windows_props" "$version_manifest" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

version = ET.parse(sys.argv[1]).findtext(".//VersionPrefix")
expected = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))["."]
assert version == expected, version
PY
grep -q 'version=0.3.5' "$control"
if grep -Eq 'version=0\.3\.[0-4]' "$control"; then
  printf 'current Windows control script must not emit an older product version\n' >&2
  exit 1
fi
grep -q 'runtime=stopped reason=not-running version=0.3.5' "$control"
if grep -q 'reason=device-validation-required' "$control"; then
  printf 'Windows control script must not report the retired device-validation gate\n' >&2
  exit 1
fi
if grep -Eiq 'Invoke-Expression|cmd(\.exe)?[[:space:]]+/c' "$control"; then
  printf 'Windows control script contains a shell-evaluation escape hatch\n' >&2
  exit 1
fi

printf 'PASS: Windows hook uses the fixed PowerShell control boundary\n'
