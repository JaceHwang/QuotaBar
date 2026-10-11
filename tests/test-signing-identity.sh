#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
selector="$plugin_root/scripts/select-signing-identity.sh"

[[ -f "$selector" ]] || {
  printf 'FAIL: signing identity selector is missing\n' >&2
  exit 1
}

# shellcheck source=../scripts/select-signing-identity.sh
source "$selector"

identity_list='  1) ABCDEF "Codex Usage Sidebar Local Signing"'
[[ "$(select_signing_identity "$identity_list")" == \
  "Codex Usage Sidebar Local Signing" ]] || {
  printf 'FAIL: local signing identity was not selected\n' >&2
  exit 1
}

unrelated_list='  1) ABCDEF "Unrelated Signing Identity"'
[[ "$(select_signing_identity "$unrelated_list")" == "-" ]] || {
  printf 'FAIL: missing identity did not fall back to ad-hoc signing\n' >&2
  exit 1
}

printf 'PASS: stable signing identity selection\n'
