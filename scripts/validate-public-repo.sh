#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_root="$repo_root/plugins/codex-usage-sidebar"
marketplace="$repo_root/.agents/plugins/marketplace.json"
manifest="$plugin_root/.codex-plugin/plugin.json"
companion="$plugin_root/assets/Codex Usage Sidebar.app"

required=(
  README.md README.zh-CN.md LICENSE CHANGELOG.md CONTRIBUTING.md SECURITY.md SUPPORT.md
  CODE_OF_CONDUCT.md .agents/plugins/marketplace.json .github/workflows/ci.yml
  .github/workflows/publish-installer.yml .github/workflows/windows-beta.yml
  docs/INSTALL.md docs/INSTALL_FOR_AGENTS.md docs/ARCHITECTURE.md docs/TROUBLESHOOTING.md
  docs/PRIVACY.md docs/images/hero.svg docs/images/placement.svg docs/images/architecture.svg
  scripts/finalize-installer-provenance.py scripts/verify-installer-package.sh
  scripts/build-macos-v032-installer.sh scripts/package-macos-v032-installer.sh
  scripts/verify-macos-v032-installer-package.sh
  scripts/build-windows-payload-manifest.py scripts/verify-windows-payload.py
  tests/test-v023-publish-freeze.sh
  plugins/codex-usage-sidebar/.codex-plugin/plugin.json
  plugins/codex-usage-sidebar/assets/PROVENANCE.json
  plugins/codex-usage-sidebar/assets/Codex\ Usage\ Sidebar.app/Contents/MacOS/CodexUsageSidebar
  plugins/codex-usage-sidebar/hooks/hooks.json plugins/codex-usage-sidebar/native/Package.swift
  plugins/codex-usage-sidebar/scripts/sidebar-control-windows.ps1
)

for relative in "${required[@]}"; do
  [[ -e "$repo_root/$relative" ]] || { printf 'missing required file: %s\n' "$relative" >&2; exit 66; }
done

"${PYTHON:-python3}" - "$repo_root" <<'PY'
import json
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
marketplace = json.loads((root / ".agents/plugins/marketplace.json").read_text())
assert marketplace["name"] == "codex-usage-sidebar"
entries = marketplace["plugins"]
assert len(entries) == 1
entry = entries[0]
assert entry["name"] == "codex-usage-sidebar"
assert entry["source"] == {"source": "local", "path": "./plugins/codex-usage-sidebar"}
assert entry["policy"] == {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}
assert entry["category"] == "Productivity"

manifest = json.loads((root / "plugins/codex-usage-sidebar/.codex-plugin/plugin.json").read_text())
assert manifest["name"] == "codex-usage-sidebar"
assert re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", manifest["version"])
assert manifest["skills"] == "./skills/"

hooks = json.loads((root / "plugins/codex-usage-sidebar/hooks/hooks.json").read_text())
session_hook = hooks["hooks"]["SessionStart"][0]["hooks"][0]
expected_mac_hook = (
    'bash "${PLUGIN_ROOT}/scripts/sidebar-control.sh" ensure '
    '--plugin-root "${PLUGIN_ROOT}" --plugin-data "${PLUGIN_DATA}" '
    '>/dev/null 2>&1 || true'
)
expected_windows_hook = (
    'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass '
    '-File "${PLUGIN_ROOT}\\scripts\\sidebar-control-windows.ps1" ensure '
    '-PluginRoot "${PLUGIN_ROOT}" -PluginData "${PLUGIN_DATA}"'
)
if session_hook.get("command") != expected_mac_hook:
    raise SystemExit("macOS session hook changed outside its stable command boundary")
if session_hook.get("commandWindows") != expected_windows_hook:
    raise SystemExit("Windows session hook differs from the fixed PowerShell boundary")

provenance_path = root / "plugins/codex-usage-sidebar/assets/PROVENANCE.json"
provenance = json.loads(provenance_path.read_text())
source_commit = provenance["sourceCommit"]
if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
    raise SystemExit("invalid provenance source commit")

if os.environ.get("CUS_REBUILT_PAYLOAD") != "1":
    executable = root / (
        "plugins/codex-usage-sidebar/assets/Codex Usage Sidebar.app/"
        "Contents/MacOS/CodexUsageSidebar"
    )
    actual_sha = hashlib.sha256(executable.read_bytes()).hexdigest()
    expected_sha = provenance["companion"]["executableSha256"]
    if actual_sha != expected_sha:
        raise SystemExit(
            f"marketplace companion hash differs from provenance: {actual_sha} != {expected_sha}"
        )
    subprocess.run(
        ["git", "-C", str(root), "cat-file", "-e", f"{source_commit}^{{commit}}"],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    source_ahead = subprocess.check_output(
        [
            "git", "-C", str(root), "diff", "--name-only", source_commit, "HEAD", "--",
            "plugins/codex-usage-sidebar",
            ":(exclude)plugins/codex-usage-sidebar/assets/Codex Usage Sidebar.app",
            ":(exclude)plugins/codex-usage-sidebar/assets/PROVENANCE.json",
        ],
        text=True,
    ).splitlines()
    installer_paths = (
        "plugins/codex-usage-sidebar/native/Package.swift",
        "plugins/codex-usage-sidebar/native/Sources/InstallerCore/",
        "plugins/codex-usage-sidebar/native/Sources/CodexUsageSidebarInstaller/",
        "plugins/codex-usage-sidebar/native/Tests/InstallerCoreTests/",
    )
    windows_only_prefixes = (
        "plugins/codex-usage-sidebar/contracts/",
        "plugins/codex-usage-sidebar/windows/",
    )
    windows_only_exact = (
        "plugins/codex-usage-sidebar/.codex-plugin/plugin.json",
        "plugins/codex-usage-sidebar/native/Tests/SidebarCoreTests/SharedContractFixtureTests.swift",
        "plugins/codex-usage-sidebar/hooks/hooks.json",
        "plugins/codex-usage-sidebar/scripts/WindowsProcessCommandLine.psm1",
        "plugins/codex-usage-sidebar/scripts/sidebar-control-windows.ps1",
        "plugins/codex-usage-sidebar/tests/test-windows-hook.sh",
    )
    unexpected_paths = [
        path for path in source_ahead
        if path != installer_paths[0]
        and path not in windows_only_exact
        and not path.startswith(installer_paths[1:])
        and not path.startswith(windows_only_prefixes)
    ]
    if unexpected_paths:
        raise SystemExit(
            "marketplace companion source differs from provenance outside the installer allowlist: "
            + ", ".join(unexpected_paths)
        )

    source_package = subprocess.check_output(
        [
            "git", "-C", str(root), "show",
            f"{source_commit}:plugins/codex-usage-sidebar/native/Package.swift",
        ],
        text=True,
    )
    expected_package = source_package.replace(
        '        .library(name: "SidebarCore", targets: ["SidebarCore"]),\n',
        '        .library(name: "SidebarCore", targets: ["SidebarCore"]),\n'
        '        .library(name: "InstallerCore", targets: ["InstallerCore"]),\n',
    ).replace(
        '        .executable(\n'
        '            name: "CodexUsageSidebar",\n'
        '            targets: ["CodexUsageSidebar"]\n'
        '        )\n',
        '        .executable(\n'
        '            name: "CodexUsageSidebar",\n'
        '            targets: ["CodexUsageSidebar"]\n'
        '        ),\n'
        '        .executable(\n'
        '            name: "CodexUsageSidebarInstaller",\n'
        '            targets: ["CodexUsageSidebarInstaller"]\n'
        '        )\n',
    ).replace(
        '        .target(name: "SidebarCore"),\n',
        '        .target(name: "SidebarCore"),\n'
        '        .target(name: "InstallerCore"),\n',
    ).replace(
        '        .executableTarget(\n'
        '            name: "CodexUsageSidebar",\n'
        '            dependencies: ["SidebarCore"]\n'
        '        ),\n',
        '        .executableTarget(\n'
        '            name: "CodexUsageSidebar",\n'
        '            dependencies: ["SidebarCore"]\n'
        '        ),\n'
        '        .executableTarget(\n'
        '            name: "CodexUsageSidebarInstaller",\n'
        '            dependencies: ["InstallerCore"]\n'
        '        ),\n',
    ).replace(
        '        .testTarget(\n'
        '            name: "SidebarCoreTests",\n'
        '            dependencies: ["SidebarCore"]\n'
        '        )\n',
        '        .testTarget(\n'
        '            name: "SidebarCoreTests",\n'
        '            dependencies: ["SidebarCore"]\n'
        '        ),\n'
        '        .testTarget(\n'
        '            name: "InstallerCoreTests",\n'
        '            dependencies: ["InstallerCore", "CodexUsageSidebarInstaller"]\n'
        '        )\n',
    )
    current_package = (
        root / "plugins/codex-usage-sidebar/native/Package.swift"
    ).read_text()
    if current_package != source_package and current_package != expected_package:
        raise SystemExit(
            "marketplace package manifest differs from the installer-only allowlist"
        )

forbidden = [
    (re.compile(r"(?<!:)/Users/[^/\s]+"), "absolute macOS user path"),
    (re.compile(r"(?:gho_|github_pat_)[A-Za-z0-9_]{20,}"), "GitHub token"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AWS key"),
    (re.compile(r"sk-[A-Za-z0-9_-]{20,}"), "API key"),
    (re.compile(r"BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY"), "private key"),
    (re.compile(r"\b(?:TBD|TODO)\b"), "placeholder"),
]

text_files = []
publishable_files = subprocess.check_output(
    [
        "git", "-C", str(root), "ls-files", "--cached", "--others",
        "--exclude-standard", "-z",
    ]
).decode("utf-8").split("\0")
for raw_relative in publishable_files:
    if not raw_relative:
        continue
    relative = Path(raw_relative)
    path = root / relative
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    text_files.append((path, text))
    if relative == Path("scripts/validate-public-repo.sh"):
        continue
    for pattern, label in forbidden:
        if pattern.search(text):
            raise SystemExit(f"{relative}: contains forbidden {label}")

link_pattern = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
for path, text in text_files:
    if path.suffix.lower() != ".md":
        continue
    for raw in link_pattern.findall(text):
        target = raw.strip().split()[0].strip("<>")
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        file_part = target.split("#", 1)[0]
        if not file_part:
            continue
        resolved = (path.parent / file_part).resolve()
        try:
            resolved.relative_to(root)
        except ValueError:
            raise SystemExit(f"{path.relative_to(root)}: link escapes repository: {target}")
        if not resolved.exists():
            raise SystemExit(f"{path.relative_to(root)}: broken relative link: {target}")

for forbidden_path in [root / ".superpowers", root / "docs/verification"]:
    if subprocess.run(
        [
            "git", "-C", str(root), "ls-files", "--error-unmatch",
            str(forbidden_path.relative_to(root)),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0:
        raise SystemExit(f"tracked private development artifact: {forbidden_path.relative_to(root)}")

publisher = (root / ".github/workflows/publish-installer.yml").read_text(encoding="utf-8")
ci_workflow = (root / ".github/workflows/ci.yml").read_text(encoding="utf-8")
if '[[ "$ARTIFACT_DIGEST" =~ ^[0-9a-f]{64}$ ]]' not in ci_workflow:
    raise SystemExit("CI workflow missing upload-artifact digest output validation")
publisher_guards = {
    "push event": "test \"$(jq -r '.event' <<<\"$run\")\" = push",
    "same-repository head": "test \"$(jq -r '.head_repository.full_name' <<<\"$run\")\" = \"$REPOSITORY\"",
    "CI workflow lookup": "repos/$REPOSITORY/actions/workflows/ci.yml",
    "CI workflow ID": "jq -r '.workflow_id'",
    "frozen v0.2.3 source": "FROZEN_V023_INSTALLER_SOURCE_COMMIT",
    "CI exact workflow path": '".github/workflows/ci.yml") ;;',
    "CI optional workflow ref": '".github/workflows/ci.yml@"*) ;;',
    "exact CI checkout": "ref: ${{ steps.trusted_ci.outputs.head_sha }}",
    "artifact listing": "actions/runs/$CI_RUN_ID/artifacts",
    "artifact ID download": "actions/artifacts/$ARTIFACT_ID/zip",
    "artifact digest verification": 'test "sha256:$downloaded_digest" = "$ARTIFACT_DIGEST"',
    "provenance finalizer": "scripts/finalize-installer-provenance.py",
    "release tag binding": "--release-tag \"$RELEASE_TAG\"",
    "SDK binding": "--sdk-version \"$INSTALLER_SDK\"",
}
for label, guard in publisher_guards.items():
    if guard not in publisher:
        raise SystemExit(f"publish installer workflow missing trusted CI run guard: {label}")

print("JSON, privacy, placeholder, and Markdown link checks passed")
PY

"${PYTHON:-python3}" - "$repo_root" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
catalog = json.loads((root / "releases/platform-release-catalog.json").read_text())
published_macos = catalog["published"]["macos"]
asset = published_macos["assets"]["installer"]
version_key = published_macos["version"].replace(".", "")
required_copy = {
    "README.md": (
        asset,
        "right-click the installer in Finder and choose Open",
    ),
    "README.zh-CN.md": (
        asset,
        "在 Finder 中右键点击安装器并选择“打开”",
    ),
}
for relative, (asset_name, gatekeeper_warning) in required_copy.items():
    text = (root / relative).read_text(encoding="utf-8")
    if asset_name not in text:
        raise SystemExit(f"{relative}: missing published macOS installer asset {asset_name}")
    if f"build-macos-v{version_key}-installer.sh" not in text:
        raise SystemExit(f"{relative}: missing reproducible macOS build command for {published_macos['version']}")
    if gatekeeper_warning not in text:
        raise SystemExit(f"{relative}: missing Finder Open warning for the local installer")
PY

workflow_files=(
  "$repo_root/.github/workflows/ci.yml"
  "$repo_root/.github/workflows/publish-installer.yml"
  "$repo_root/.github/workflows/windows-beta.yml"
)
if [[ -x /usr/bin/ruby ]]; then
  /usr/bin/ruby -ryaml -e '
    ARGV.each do |path|
      YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
    end
  ' "${workflow_files[@]}"
else
  "${PYTHON:-python3}" - "${workflow_files[@]}" <<'PY'
import sys
import yaml

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        events = tuple(yaml.parse(handle))
    if any(isinstance(event, yaml.events.AliasEvent) for event in events):
        raise SystemExit(f"{path}: YAML aliases are not allowed")
    with open(path, encoding="utf-8") as handle:
        yaml.safe_load(handle)
PY
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  /usr/bin/plutil -lint "$companion/Contents/Info.plist" >/dev/null
  /usr/bin/codesign --verify --deep --strict "$companion"
  [[ -x "$companion/Contents/MacOS/CodexUsageSidebar" ]]
else
  printf 'SKIP: companion signature verification requires macOS\n'
fi
[[ -x "$plugin_root/scripts/sidebar-control.sh" ]]
[[ -x "$plugin_root/scripts/build-companion.sh" ]]
[[ -x "$repo_root/scripts/build-installer.sh" ]]
[[ -x "$repo_root/scripts/package-installer.sh" ]]
[[ -x "$repo_root/scripts/verify-installer-package.sh" ]]
[[ -x "$repo_root/scripts/build-macos-v032-installer.sh" ]]
[[ -x "$repo_root/scripts/package-macos-v032-installer.sh" ]]
[[ -x "$repo_root/scripts/verify-macos-v032-installer-package.sh" ]]
[[ -x "$repo_root/scripts/build-macos-v033-installer.sh" ]]
[[ -x "$repo_root/scripts/package-macos-v033-installer.sh" ]]
[[ -x "$repo_root/scripts/verify-macos-v033-installer-package.sh" ]]
[[ -x "$repo_root/scripts/finalize-installer-provenance.py" ]]
[[ -x "$repo_root/scripts/build-windows-payload-manifest.py" ]]
[[ -x "$repo_root/scripts/verify-windows-payload.py" ]]
[[ -x "$repo_root/tests/test-windows-beta-workflow.sh" ]]
[[ -x "$repo_root/tests/test-windows-payload-manifest.sh" ]]
[[ -x "$repo_root/tests/test-v023-publish-freeze.sh" ]]
[[ -x "$plugin_root/tests/test-windows-hook.sh" ]]

bash "$repo_root/tests/test-windows-beta-workflow.sh"
bash "$repo_root/tests/test-windows-payload-manifest.sh"
bash "$repo_root/tests/test-v023-publish-freeze.sh"
bash "$plugin_root/tests/test-windows-hook.sh"

if [[ -x /usr/bin/xmllint ]]; then
  for svg in "$repo_root"/docs/images/*.svg; do
    /usr/bin/xmllint --noout "$svg"
  done
else
  "${PYTHON:-python3}" - "$repo_root"/docs/images/*.svg <<'PY'
import sys
import xml.etree.ElementTree as ET

for path in sys.argv[1:]:
    ET.parse(path)
PY
fi

printf 'PASS: public repository layout, manifests, links, privacy, SVG, and companion signature\n'
