#!/usr/bin/env bash
set -euo pipefail

label="com.jace.codex-usage-sidebar"
action="${1:-}"
if [[ -z "$action" ]]; then
  printf 'usage: %s {ensure|status|repair|uninstall} [--plugin-root PATH] [--plugin-data PATH]\n' "$0" >&2
  exit 64
fi
shift

plugin_root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
plugin_data="${PLUGIN_DATA:-${CLAUDE_PLUGIN_DATA:-}}"

while (($#)); do
  case "$1" in
    --plugin-root)
      [[ $# -ge 2 ]] || { printf 'missing value for --plugin-root\n' >&2; exit 64; }
      plugin_root="$2"
      shift 2
      ;;
    --plugin-data)
      [[ $# -ge 2 ]] || { printf 'missing value for --plugin-data\n' >&2; exit 64; }
      plugin_data="$2"
      shift 2
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done

stable_script_directory="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "$plugin_root" && -f "$stable_script_directory/plugin-root.txt" ]]; then
  IFS= read -r plugin_root <"$stable_script_directory/plugin-root.txt"
fi

user_home="${CUS_TEST_HOME:-$HOME}"
user_uid="${CUS_TEST_UID:-$(/usr/bin/id -u)}"
launchctl_bin="${CUS_TEST_LAUNCHCTL:-/bin/launchctl}"
codesign_bin="${CUS_TEST_CODESIGN:-/usr/bin/codesign}"
install_root="$user_home/Library/Application Support/CodexUsageSidebar"
installed_app="$install_root/Codex Usage Sidebar.app"
installed_binary="$installed_app/Contents/MacOS/CodexUsageSidebar"
payload_fingerprint_file="$install_root/payload.sha256"
agent_plist="$user_home/Library/LaunchAgents/$label.plist"
domain="gui/$user_uid"
service="$domain/$label"

if [[ -z "$plugin_data" ]]; then
  plugin_data="$install_root/Data"
fi
runtime_state_file="$plugin_data/runtime-state.txt"
codex_home="$(/usr/bin/dirname "$plugin_data")/CodexHome"

verify_bundle_signature() {
  local bundle="$1"
  local description="$2"
  "$codesign_bin" --verify --deep --strict "$bundle" >/dev/null 2>&1 || {
    printf '%s has an invalid code signature: %s\n' "$description" "$bundle" >&2
    return 1
  }
}

source_payload_fingerprint() {
  {
    /usr/bin/shasum -a 256 "$source_app/Contents/Info.plist"
    /usr/bin/shasum -a 256 "$source_binary"
  } | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

resolve_install_signing_identity() {
  local selector="$plugin_root/scripts/select-signing-identity.sh"
  if [[ ! -f "$selector" ]]; then
    printf '%s\n' '-'
    return
  fi

  # shellcheck source=select-signing-identity.sh
  source "$selector"
  if [[ ${CUS_TEST_SIGNING_IDENTITIES+x} == x ]]; then
    select_signing_identity "$CUS_TEST_SIGNING_IDENTITIES"
  else
    select_signing_identity
  fi
}

sign_copied_payload() {
  local bundle="$1"
  local signing_identity
  signing_identity="$(resolve_install_signing_identity)"
  if [[ "$signing_identity" != "-" ]]; then
    "$codesign_bin" \
      --force \
      --deep \
      --sign "$signing_identity" \
      "$bundle"
  fi
}

require_plugin_payload() {
  [[ -n "$plugin_root" ]] || {
    printf 'plugin root is required; pass --plugin-root or set PLUGIN_ROOT\n' >&2
    exit 64
  }

  source_app="$plugin_root/assets/Codex Usage Sidebar.app"
  source_binary="$source_app/Contents/MacOS/CodexUsageSidebar"
  [[ -f "$source_app/Contents/Info.plist" ]] || {
    printf 'companion Info.plist is missing: %s\n' "$source_app/Contents/Info.plist" >&2
    exit 66
  }
  /usr/bin/plutil -lint "$source_app/Contents/Info.plist" >/dev/null || {
    printf 'companion Info.plist is malformed: %s\n' "$source_app/Contents/Info.plist" >&2
    exit 66
  }
  [[ -x "$source_binary" ]] || {
    printf 'companion executable is missing: %s\n' "$source_binary" >&2
    exit 66
  }
  verify_bundle_signature "$source_app" "source companion" || exit 65
}

xml_escape() {
  /usr/bin/sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    <<<"$1"
}

write_agent_plist() {
  local temp_plist="$agent_plist.tmp.$$"
  local escaped_binary escaped_data
  escaped_binary="$(xml_escape "$installed_binary")"
  escaped_data="$(xml_escape "$plugin_data")"

  /bin/cat >"$temp_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$escaped_binary</string>
    <string>--plugin-data</string>
    <string>$escaped_data</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>$escaped_data/sidebar.log</string>
  <key>StandardErrorPath</key>
  <string>$escaped_data/sidebar-error.log</string>
</dict>
</plist>
PLIST
  /usr/bin/plutil -lint "$temp_plist" >/dev/null
  /bin/mv -f "$temp_plist" "$agent_plist"
}

payload_matches() {
  local installed_fingerprint source_fingerprint
  [[ -x "$installed_binary" ]] || return 1
  [[ -f "$payload_fingerprint_file" ]] || return 1
  IFS= read -r installed_fingerprint <"$payload_fingerprint_file"
  source_fingerprint="$(source_payload_fingerprint)"
  [[ "$installed_fingerprint" == "$source_fingerprint" ]]
}

sync_payload() {
  local force_sync="${1:-false}"
  local source_fingerprint
  local temp_app="$install_root/.Codex Usage Sidebar.app.tmp.$$"
  local previous_app="$install_root/.Codex Usage Sidebar.app.previous.$$"
  source_fingerprint="$(source_payload_fingerprint)"
  /bin/mkdir -p \
    "$install_root" \
    "$plugin_data" \
    "$codex_home" \
    "$user_home/Library/LaunchAgents"

  if [[ "$force_sync" == "true" ]] || ! payload_matches; then
    if [[ "$temp_app" != "$install_root/"* ]]; then
      printf 'refusing unsafe temporary path: %s\n' "$temp_app" >&2
      exit 70
    fi
    /bin/rm -rf "$temp_app"
    /bin/rm -rf "$previous_app"
    /usr/bin/ditto "$source_app" "$temp_app"
    sign_copied_payload "$temp_app" || {
      /bin/rm -rf "$temp_app"
      exit 65
    }
    verify_bundle_signature "$temp_app" "copied companion" || {
      /bin/rm -rf "$temp_app"
      exit 65
    }
    if [[ -e "$installed_app" ]]; then
      /bin/mv "$installed_app" "$previous_app"
    fi
    if ! /bin/mv "$temp_app" "$installed_app"; then
      if [[ -e "$previous_app" ]]; then
        /bin/mv "$previous_app" "$installed_app"
      fi
      exit 74
    fi
    /bin/rm -rf "$previous_app"
    printf '%s\n' "$source_fingerprint" \
      >"$payload_fingerprint_file.tmp.$$"
    /bin/mv -f \
      "$payload_fingerprint_file.tmp.$$" \
      "$payload_fingerprint_file"
  fi

  verify_bundle_signature "$installed_app" "installed companion" || exit 65

  local installed_control="$install_root/sidebar-control.sh"
  if [[ ! -e "$installed_control" || ! "$0" -ef "$installed_control" ]]; then
    /bin/cp "$0" "$installed_control"
  fi
  /bin/chmod 755 "$installed_control" "$installed_binary"
  printf '%s\n' "$plugin_root" >"$install_root/plugin-root.txt.tmp.$$"
  /bin/mv -f "$install_root/plugin-root.txt.tmp.$$" "$install_root/plugin-root.txt"
  write_agent_plist
}

start_service() {
  if ! "$launchctl_bin" print "$service" >/dev/null 2>&1; then
    "$launchctl_bin" bootstrap "$domain" "$agent_plist"
  fi
}

running_service_pid() {
  "$launchctl_bin" print "$service" 2>/dev/null | /usr/bin/awk \
    '/^[[:space:]]*pid =/ { print $3; exit }'
}

print_runtime_diagnostic() {
  local service_pid state_pid attempt
  service_pid="$(running_service_pid || true)"
  if [[ -n "$service_pid" ]]; then
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      if [[ -f "$runtime_state_file" ]]; then
        state_pid="$(/usr/bin/awk -F'[ =]' 'NR == 1 { print $2 }' "$runtime_state_file")"
        if [[ "$state_pid" == "$service_pid" ]]; then
          /bin/cat "$runtime_state_file"
          return
        fi
      fi
      /bin/sleep 0.25
    done
  fi

  # Older companions do not publish runtime state; retain a labeled fallback.
  printf 'standalone='
  "$installed_binary" --diagnostic-once
}

stop_service_before_payload_upgrade() {
  if ! payload_matches && \
      "$launchctl_bin" print "$service" >/dev/null 2>&1
  then
    "$launchctl_bin" bootout "$service" >/dev/null 2>&1 || true
  fi
}

ensure() {
  if [[ -f "$install_root/standalone-mode" ]]; then
    printf 'Standalone Codex Quota mode is active; legacy companion remains stopped.\n'
    return
  fi
  require_plugin_payload
  stop_service_before_payload_upgrade
  sync_payload
  start_service
  printf 'Codex Usage Sidebar is installed and running.\n'
}

status() {
  if [[ ! -x "$installed_binary" ]]; then
    printf 'not installed\n'
    exit 1
  fi
  verify_bundle_signature "$installed_app" "installed companion" || exit 65
  if "$launchctl_bin" print "$service" >/dev/null 2>&1; then
    print_runtime_diagnostic
    printf 'installed and loaded: %s\n' "$installed_app"
  else
    printf 'installed but not loaded: %s\n' "$installed_app"
    exit 1
  fi
}

repair() {
  require_plugin_payload
  "$launchctl_bin" bootout "$service" >/dev/null 2>&1 || true
  sync_payload true
  "$launchctl_bin" bootstrap "$domain" "$agent_plist"
  "$launchctl_bin" kickstart -k "$service"
  print_runtime_diagnostic
  printf 'Codex Usage Sidebar was repaired.\n'
}

uninstall() {
  "$launchctl_bin" bootout "$service" >/dev/null 2>&1 || true
  if [[ "$agent_plist" != "$user_home/Library/LaunchAgents/$label.plist" ]]; then
    printf 'refusing unsafe LaunchAgent path: %s\n' "$agent_plist" >&2
    exit 70
  fi
  if [[ "$install_root" != "$user_home/Library/Application Support/CodexUsageSidebar" ]]; then
    printf 'refusing unsafe install path: %s\n' "$install_root" >&2
    exit 70
  fi
  /bin/rm -f "$agent_plist"
  /bin/rm -rf "$install_root"
  printf 'Codex Usage Sidebar was uninstalled.\n'
}

case "$action" in
  ensure) ensure ;;
  status) status ;;
  repair|uninstall)
    if [[ -f "$install_root/standalone-mode" ]]; then
      printf 'Standalone mode owns this account directory; use standalone migration controls.\n' >&2
      exit 65
    fi
    "$action" ;;
  *)
    printf 'unknown action: %s\n' "$action" >&2
    exit 64
    ;;
esac
