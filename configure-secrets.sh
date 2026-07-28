#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

test "$(id -u)" -eq 0 || {
  echo "Run with sudo: sudo ./configure-secrets.sh AUTH_JSON" >&2
  exit 77
}
auth_source=${1:-}
test "$#" -eq 1 || {
  echo "usage: sudo ./configure-secrets.sh AUTH_JSON" >&2
  exit 64
}
test -f "$auth_source" && test ! -L "$auth_source" ||
  { echo "Input must be a regular, non-symlink file: $auth_source" >&2; exit 64; }
test -f /var/lib/paperclip-appliance/complete ||
  { echo "Run sudo ./bootstrap.sh first" >&2; exit 69; }

jq -e '
  type == "object" and
  (.version | type == "number") and
  (.providers | type == "object") and
  (.active_provider | type == "string" and length > 0) and
  (.credential_pool | type == "object")
' "$auth_source" >/dev/null ||
  { echo "AUTH_JSON is not a valid Hermes credential file" >&2; exit 65; }

/usr/local/sbin/paperclip-hermes-credential-install "$auth_source"
echo "Provider credential installed."
echo "Run the final check: sudo ./verify.sh"
