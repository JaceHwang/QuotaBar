#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
control_script="$repo_root/scripts/sidebar-control.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/Codex Usage Sidebar Test.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_contains() {
  local needle="$1"
  local haystack_file="$2"
  /usr/bin/grep -Fq -- "$needle" "$haystack_file" ||
    fail "expected '$needle' in $haystack_file"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "expected path to be absent: $1"
}

assert_before() {
  local first="$1"
  local second="$2"
  local haystack_file="$3"
  local first_line second_line
  first_line="$(/usr/bin/grep -nF -- "$first" "$haystack_file" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
  second_line="$(/usr/bin/grep -nF -- "$second" "$haystack_file" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
  [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]] ||
    fail "expected '$first' before '$second' in $haystack_file"
}

fake_home="$fixture_root/home"
fake_plugin="$fixture_root/plugin"
fake_app="$fake_plugin/assets/Codex Usage Sidebar.app"
fake_launchctl="$fixture_root/launchctl"
fake_codesign="$fixture_root/codesign"
codesign_log="$fixture_root/codesign.log"
launchctl_log="$fixture_root/launchctl.log"
launchctl_state="$fixture_root/launchctl.loaded"
app_log="$fixture_root/app.log"
operation_log="$fixture_root/operation.log"

mkdir -p \
  "$fake_home/Library/Application Support" \
  "$fake_home/Library/LaunchAgents" \
  "$fake_plugin/scripts" \
  "$fake_app/Contents/MacOS"

cp "$repo_root/.codex-plugin/plugin.json" "$fake_plugin/plugin.json"
cp "$repo_root/scripts/select-signing-identity.sh" "$fake_plugin/scripts/"

cat >"$fake_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.jace.codex-usage-sidebar</string>
  <key>CFBundleShortVersionString</key><string>0.1.0-test</string>
  <key>CFBundleExecutable</key><string>CodexUsageSidebar</string>
</dict></plist>
PLIST

cat >"$fake_app/Contents/MacOS/CodexUsageSidebar" <<'APP'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CUS_TEST_APP_LOG:?}"
printf 'app %s\n' "$*" >>"${CUS_TEST_OPERATION_LOG:?}"
exit 0
APP
chmod +x "$fake_app/Contents/MacOS/CodexUsageSidebar"

cat >"$fake_launchctl" <<'LAUNCHCTL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${CUS_TEST_LAUNCHCTL_LOG:?}"
printf 'launchctl %s\n' "$*" >>"${CUS_TEST_OPERATION_LOG:?}"
case "${1:-}" in
  print)
    [[ -f "${CUS_TEST_LAUNCHCTL_STATE:?}" ]]
    ;;
  bootstrap)
    : >"${CUS_TEST_LAUNCHCTL_STATE:?}"
    ;;
  bootout)
    rm -f "${CUS_TEST_LAUNCHCTL_STATE:?}"
    ;;
  kickstart)
    [[ -f "${CUS_TEST_LAUNCHCTL_STATE:?}" ]]
    ;;
esac
LAUNCHCTL
chmod +x "$fake_launchctl"

cat >"$fake_codesign" <<'CODESIGN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${CUS_TEST_CODESIGN_LOG:?}"
bundle="${*: -1}"
[[ ! -e "$bundle/Contents/invalid-signature" ]]
CODESIGN
chmod +x "$fake_codesign"

export CUS_TEST_HOME="$fake_home"
export CUS_TEST_LAUNCHCTL="$fake_launchctl"
export CUS_TEST_CODESIGN="$fake_codesign"
export CUS_TEST_CODESIGN_LOG="$codesign_log"
export CUS_TEST_LAUNCHCTL_LOG="$launchctl_log"
export CUS_TEST_LAUNCHCTL_STATE="$launchctl_state"
export CUS_TEST_APP_LOG="$app_log"
export CUS_TEST_OPERATION_LOG="$operation_log"
export CUS_TEST_UID=501
export CUS_TEST_SIGNING_IDENTITIES='  1) TEST "Codex Usage Sidebar Local Signing"'

[[ -x "$control_script" ]] || fail "control script is missing or not executable"

"$control_script" ensure --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"

installed_root="$fake_home/Library/Application Support/CodexUsageSidebar"
installed_app="$installed_root/Codex Usage Sidebar.app"
agent_plist="$fake_home/Library/LaunchAgents/com.jace.codex-usage-sidebar.plist"

assert_file "$installed_app/Contents/Info.plist"
assert_file "$installed_app/Contents/MacOS/CodexUsageSidebar"
assert_file "$installed_root/sidebar-control.sh"
assert_file "$agent_plist"
[[ -d "$fixture_root/CodexHome" ]] || fail "plugin CodexHome was not created"
/usr/bin/plutil -lint "$agent_plist" >/dev/null
assert_contains "bootstrap gui/501 $agent_plist" "$launchctl_log"
assert_contains "--verify --deep --strict $fake_app" "$codesign_log"
assert_contains "--verify --deep --strict $installed_app" "$codesign_log"
assert_contains "--sign Codex Usage Sidebar Local Signing" "$codesign_log"
assert_file "$installed_root/payload.sha256"
"$control_script" status --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"

rm -f "$launchctl_state"
if "$control_script" status --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"; then
  fail "status unexpectedly succeeded while the fake LaunchAgent was absent"
fi
"$control_script" ensure --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"

first_hash="$(/usr/bin/shasum -a 256 "$installed_app/Contents/MacOS/CodexUsageSidebar" | /usr/bin/awk '{print $1}')"
"$control_script" ensure --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"
second_hash="$(/usr/bin/shasum -a 256 "$installed_app/Contents/MacOS/CodexUsageSidebar" | /usr/bin/awk '{print $1}')"
[[ "$first_hash" == "$second_hash" ]] || fail "idempotent ensure changed the installed executable"

: >"$operation_log"
cat >"$fake_app/Contents/MacOS/CodexUsageSidebar" <<'UPGRADED_APP'
#!/usr/bin/env bash
printf 'upgraded %s\n' "$*" >>"${CUS_TEST_APP_LOG:?}"
printf 'app upgraded %s\n' "$*" >>"${CUS_TEST_OPERATION_LOG:?}"
UPGRADED_APP
chmod +x "$fake_app/Contents/MacOS/CodexUsageSidebar"
/usr/libexec/PlistBuddy \
  -c 'Set :CFBundleShortVersionString 0.2.0-test' \
  "$fake_app/Contents/Info.plist"

"$control_script" ensure --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"
assert_contains "0.2.0-test" "$installed_app/Contents/Info.plist"
assert_before \
  "launchctl bootout gui/501/com.jace.codex-usage-sidebar" \
  "launchctl bootstrap gui/501" \
  "$operation_log"

cat >"$fake_app/Contents/MacOS/CodexUsageSidebar" <<'REPAIRED_APP'
#!/usr/bin/env bash
printf 'repaired %s\n' "$*" >>"${CUS_TEST_APP_LOG:?}"
printf 'app repaired %s\n' "$*" >>"${CUS_TEST_OPERATION_LOG:?}"
REPAIRED_APP
chmod +x "$fake_app/Contents/MacOS/CodexUsageSidebar"
/usr/libexec/PlistBuddy \
  -c 'Set :CFBundleShortVersionString 0.3.0-test' \
  "$fake_app/Contents/Info.plist"

"$control_script" repair --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"
assert_contains "0.3.0-test" "$installed_app/Contents/Info.plist"
assert_contains "repaired" "$installed_app/Contents/MacOS/CodexUsageSidebar"
assert_contains "bootout gui/501/com.jace.codex-usage-sidebar" "$launchctl_log"
assert_contains "kickstart -k gui/501/com.jace.codex-usage-sidebar" "$launchctl_log"
assert_contains "repaired --diagnostic-once" "$app_log"

# The installed controller is also the repair entry point after a plugin update.
# It must not fail while synchronizing itself onto the same destination path.
cat >"$fake_app/Contents/MacOS/CodexUsageSidebar" <<'INSTALLED_CONTROLLER_REPAIRED_APP'
#!/usr/bin/env bash
printf 'installed-controller-repaired %s\n' "$*" >>"${CUS_TEST_APP_LOG:?}"
INSTALLED_CONTROLLER_REPAIRED_APP
chmod +x "$fake_app/Contents/MacOS/CodexUsageSidebar"
/usr/libexec/PlistBuddy \
  -c 'Set :CFBundleShortVersionString 0.4.0-test' \
  "$fake_app/Contents/Info.plist"

"$installed_root/sidebar-control.sh" repair --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"
assert_contains "0.4.0-test" "$installed_app/Contents/Info.plist"
assert_contains "installed-controller-repaired" "$installed_app/Contents/MacOS/CodexUsageSidebar"
assert_contains "installed-controller-repaired --diagnostic-once" "$app_log"

malformed_plugin="$fixture_root/malformed plugin"
mkdir -p "$malformed_plugin/assets/Codex Usage Sidebar.app/Contents/MacOS"
cp "$fake_app/Contents/Info.plist" \
  "$malformed_plugin/assets/Codex Usage Sidebar.app/Contents/Info.plist"
before_malformed_hash="$(/usr/bin/shasum -a 256 "$installed_app/Contents/MacOS/CodexUsageSidebar" | /usr/bin/awk '{print $1}')"
if "$control_script" ensure --plugin-root "$malformed_plugin" --plugin-data "$fixture_root/plugin-data"; then
  fail "malformed source bundle unexpectedly installed"
fi
after_malformed_hash="$(/usr/bin/shasum -a 256 "$installed_app/Contents/MacOS/CodexUsageSidebar" | /usr/bin/awk '{print $1}')"
[[ "$before_malformed_hash" == "$after_malformed_hash" ]] ||
  fail "malformed source mutated the installed app"

invalid_plugin="$fixture_root/invalid signature plugin"
cp -R "$fake_plugin" "$invalid_plugin"
touch "$invalid_plugin/assets/Codex Usage Sidebar.app/Contents/invalid-signature"
before_invalid_hash="$(/usr/bin/shasum -a 256 "$installed_app/Contents/MacOS/CodexUsageSidebar" | /usr/bin/awk '{print $1}')"
if "$control_script" ensure --plugin-root "$invalid_plugin" --plugin-data "$fixture_root/plugin-data"; then
  fail "invalidly signed source bundle unexpectedly installed"
fi
after_invalid_hash="$(/usr/bin/shasum -a 256 "$installed_app/Contents/MacOS/CodexUsageSidebar" | /usr/bin/awk '{print $1}')"
[[ "$before_invalid_hash" == "$after_invalid_hash" ]] ||
  fail "invalidly signed source mutated the installed app"

touch "$installed_root/standalone-mode"
before_standalone_log="$(wc -l < "$launchctl_log")"
"$control_script" ensure --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"
after_standalone_log="$(wc -l < "$launchctl_log")"
[[ "$before_standalone_log" == "$after_standalone_log" ]] || fail "standalone mode restarted legacy companion"
rm "$installed_root/standalone-mode"

sentinel="$fake_home/Library/Application Support/keep-me.txt"
printf 'keep\n' >"$sentinel"
"$control_script" uninstall --plugin-root "$fake_plugin" --plugin-data "$fixture_root/plugin-data"
assert_not_exists "$installed_root"
assert_not_exists "$agent_plist"
assert_file "$sentinel"

if /usr/bin/grep -Fq "/Applications/ChatGPT.app" "$launchctl_log"; then
  fail "control command targeted the signed Codex application"
fi

printf 'PASS: sidebar-control safely ensures, repairs, reports, and uninstalls\n'
