#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python="${PYTHON:-python3}"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
payload="$fixture_root/payload"
mkdir -p "$payload"

printf 'host' > "$payload/CodexUsageSidebar.Windows.exe"
printf 'control' > "$payload/CodexUsageSidebar.Control.exe"
printf 'runtime' > "$payload/codex.exe"
printf '{"schemaVersion":1,"builds":[]}' > "$payload/selectors.json"
runtime_sha="$("$python" - "$payload/codex.exe" <<'PY'
import hashlib
import sys

print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)"
source_commit="0123456789abcdef0123456789abcdef01234567"
codex_source="https://github.com/openai/codex/releases/download/rust-v0.147.0/codex-x86_64-pc-windows-msvc.exe"

missing_payload="$fixture_root/missing-payload"
mkdir -p "$missing_payload"
cp "$payload/CodexUsageSidebar.Windows.exe" "$missing_payload/"
if "$python" "$repo_root/scripts/build-windows-payload-manifest.py" \
  --payload-dir "$missing_payload" --version 0.3.1 --architecture x64 \
  --source-commit "$source_commit" --codex-source "$codex_source" \
  --codex-sha256 "$runtime_sha" >/dev/null 2>&1; then
  printf 'missing required payload unexpectedly succeeded\n' >&2
  exit 1
fi

if "$python" "$repo_root/scripts/build-windows-payload-manifest.py" \
  --payload-dir "$payload" --version 0.3.0 --architecture x64 \
  --source-commit "$source_commit" --codex-source "$codex_source" \
  --codex-sha256 "$runtime_sha" >/dev/null 2>&1; then
  printf 'version mismatch unexpectedly succeeded\n' >&2
  exit 1
fi

if "$python" "$repo_root/scripts/build-windows-payload-manifest.py" \
  --payload-dir "$payload" --version 0.3.1 --architecture x64 \
  --source-commit invalid --codex-source "$codex_source" \
  --codex-sha256 "$runtime_sha" >/dev/null 2>&1; then
  printf 'invalid source commit unexpectedly succeeded\n' >&2
  exit 1
fi

if "$python" "$repo_root/scripts/build-windows-payload-manifest.py" \
  --payload-dir "$payload" --version 0.3.1 --architecture x64 \
  --source-commit "$source_commit" --codex-source https://example.invalid/codex.exe \
  --codex-sha256 "$runtime_sha" >/dev/null 2>&1; then
  printf 'non-OpenAI Codex runtime source unexpectedly succeeded\n' >&2
  exit 1
fi

if "$python" "$repo_root/scripts/build-windows-payload-manifest.py" \
  --payload-dir "$payload" --version 0.3.1 --architecture x64 \
  --source-commit "$source_commit" --codex-source "$codex_source" \
  --codex-sha256 "$(printf '0%.0s' {1..64})" >/dev/null 2>&1; then
  printf 'incorrect Codex runtime digest unexpectedly succeeded\n' >&2
  exit 1
fi

outside="$fixture_root/outside.txt"
printf 'outside' > "$outside"
ln -s "$outside" "$payload/linked-outside.txt"
if [[ -L "$payload/linked-outside.txt" ]]; then
  if "$python" "$repo_root/scripts/build-windows-payload-manifest.py" \
    --payload-dir "$payload" --version 0.3.1 --architecture x64 \
    --source-commit "$source_commit" --codex-source "$codex_source" \
    --codex-sha256 "$runtime_sha" >/dev/null 2>&1; then
    printf 'linked payload escape unexpectedly succeeded\n' >&2
    exit 1
  fi
else
  printf 'SKIP: host cannot create symbolic links\n'
fi
rm "$payload/linked-outside.txt"

"$python" "$repo_root/scripts/build-windows-payload-manifest.py" \
  --payload-dir "$payload" --version 0.3.1 --architecture x64 \
  --source-commit "$source_commit" --codex-source "$codex_source" \
  --codex-sha256 "$runtime_sha"
"$python" "$repo_root/scripts/verify-windows-payload.py" "$payload"

"$python" - "$payload/windows-payload.json" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert manifest["status"] == "device-test"
assert manifest["realDeviceValidated"] is False
assert manifest["publishableInstaller"] is False
PY

cp "$payload/windows-payload.json" "$fixture_root/valid-manifest.json"
"$python" - "$payload/windows-payload.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
manifest["publishableInstaller"] = True
path.write_text(json.dumps(manifest), encoding="utf-8")
PY
if "$python" "$repo_root/scripts/verify-windows-payload.py" "$payload" >/dev/null 2>&1; then
  printf 'publishable device payload unexpectedly succeeded\n' >&2
  exit 1
fi
cp "$fixture_root/valid-manifest.json" "$payload/windows-payload.json"

printf 'tampered' > "$payload/CodexUsageSidebar.Control.exe"
if "$python" "$repo_root/scripts/verify-windows-payload.py" "$payload" >/dev/null 2>&1; then
  printf 'digest mismatch unexpectedly succeeded\n' >&2
  exit 1
fi

printf 'PASS: Windows payload negative and positive manifest tests\n'
