#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

snapshot_validate_auth_source() {
  local auth_source=$1
  test -f "$auth_source" && test ! -L "$auth_source" || return 64
  jq -e '
    type == "object" and
    (.version | type == "number") and
    (.providers | type == "object") and
    (.active_provider | type == "string" and length > 0) and
    (.credential_pool | type == "object")
  ' "$auth_source" >/dev/null
}

snapshot_verify_profiles() {
  local agents_root=$1
  local hermes_command=$2
  local runuser_command=$3
  local expected_identity=$4
  local slug home status

  for slug in operations research production qa; do
    home=$agents_root/$slug/home
    test -d "$home" || {
      echo "missing profile: $slug" >&2
      return 69
    }
    test -f "$home/auth.json" || {
      echo "missing credential: $slug" >&2
      return 69
    }
    test "$(stat -c '%a:%U:%G' "$home/auth.json")" = "$expected_identity" || {
      echo "invalid credential ownership or mode: $slug" >&2
      return 69
    }
    test ! -e "$home/CREDENTIAL_REQUIRED" || {
      echo "credential requirement marker remains: $slug" >&2
      return 69
    }
    status=$("$runuser_command" -u paperclip -- env -i \
      HOME=/var/lib/paperclip HERMES_HOME="$home" \
      PATH="$(dirname "$hermes_command"):/usr/bin:/bin" \
      "$hermes_command" auth status openai-codex)
    test "$status" = "openai-codex: logged in" || {
      echo "OpenAI Codex credential is not usable by profile: $slug" >&2
      return 69
    }
  done
}

snapshot_write_marker() (
  set -Eeuo pipefail
  local state_dir=$1
  local expected_identity=$2
  local marker_tmp

  test -d "$state_dir"
  marker_tmp=$(mktemp "$state_dir/.snapshot-only-commissioned.XXXXXX")
  trap 'rm -f -- "$marker_tmp"' EXIT HUP INT TERM
  printf '%s\n' \
    'mode=snapshot-only' \
    'accepted-risk=provider-snapshots' \
    "configured-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$marker_tmp"
  chmod 0600 "$marker_tmp"
  if [ "$expected_identity" = 600:root:root ]; then
    chown root:root "$marker_tmp"
  fi
  test "$(stat -c '%a:%U:%G' "$marker_tmp")" = "$expected_identity"
  mv -f -- "$marker_tmp" "$state_dir/snapshot-only-commissioned"
)

snapshot_commission() {
  local auth_source=$1
  local credential_installer=$2
  local state_dir=$3
  local agents_root=$4
  local hermes_command=$5
  local runuser_command=$6
  local profile_identity=$7
  local marker_identity=$8

  snapshot_validate_auth_source "$auth_source" || {
    echo "AUTH_JSON is not a valid regular, non-symlink Hermes credential file" >&2
    return 65
  }
  "$credential_installer" "$auth_source" || return
  snapshot_verify_profiles "$agents_root" "$hermes_command" \
    "$runuser_command" "$profile_identity" || return
  snapshot_write_marker "$state_dir" "$marker_identity" || return
}

snapshot_main() {
  local auth_source state_dir hermes_command

  test "$(id -u)" -eq 0 || {
    echo "Run with sudo: sudo ./configure-snapshot-only.sh --accept-provider-snapshot-risk AUTH_JSON" >&2
    exit 77
  }
  test "$#" -eq 2 && [ "$1" = --accept-provider-snapshot-risk ] || {
    echo "usage: sudo ./configure-snapshot-only.sh --accept-provider-snapshot-risk AUTH_JSON" >&2
    exit 64
  }
  auth_source=$2
  state_dir=/var/lib/paperclip-appliance
  test -f "$state_dir/complete" || {
    echo "Run sudo ./bootstrap.sh first" >&2
    exit 69
  }
  if grep -qx 'PAPERCLIP_OFFSITE_REQUIRED=true' \
      /etc/paperclip/offsite-backup.conf 2>/dev/null ||
     [ -e "$state_dir/configured-boot-id" ]; then
    echo "Production commissioning is present or in progress; continue with configure-secrets.sh" >&2
    exit 65
  fi

  # shellcheck disable=SC1091
  . "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/appliance.lock"
  hermes_command=/opt/hermes-agent/$HERMES_COMMIT/venv/bin/hermes
  snapshot_commission "$auth_source" \
    /usr/local/sbin/paperclip-hermes-credential-install \
    "$state_dir" /var/lib/paperclip/agents "$hermes_command" \
    /usr/sbin/runuser 600:paperclip:paperclip 600:root:root

  echo "Provider credential installed and locally validated in four isolated profiles."
  echo "Operator accepted VM-provider snapshots instead of verified offsite backup."
  echo "Run now: sudo ./verify-snapshot-only.sh"
  echo "PRODUCTION: NOT READY (SNAPSHOT-ONLY)"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  snapshot_main "$@"
fi
