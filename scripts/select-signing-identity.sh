#!/usr/bin/env bash

codex_usage_signing_identity='Codex Usage Sidebar Local Signing'

select_signing_identity() {
  local identity_list="${1-}"
  if (($# == 0)); then
    identity_list="$(
      /usr/bin/security find-identity -v -p codesigning 2>/dev/null || true
    )"
  fi

  if /usr/bin/grep -Fq \
    "\"$codex_usage_signing_identity\"" \
    <<<"$identity_list"
  then
    printf '%s\n' "$codex_usage_signing_identity"
  else
    printf '%s\n' '-'
  fi
}
