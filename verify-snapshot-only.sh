#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

test "$(id -u)" -eq 0 || {
  echo "Run with sudo: sudo ./verify-snapshot-only.sh" >&2
  exit 77
}
test "$#" -eq 0 || {
  echo "usage: sudo ./verify-snapshot-only.sh" >&2
  exit 64
}

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$repo/appliance.lock"
fail() { echo "FAIL: $*" >&2; exit 1; }

"$repo/verify.sh" --platform-only

marker=/var/lib/paperclip-appliance/snapshot-only-commissioned
test -f "$marker" || fail "snapshot-only commissioning marker is missing"
test ! -L "$marker" || fail "snapshot-only commissioning marker is a symlink"
test "$(stat -c '%a:%U:%G' "$marker")" = 600:root:root ||
  fail "snapshot-only commissioning marker permissions"
grep -qx 'mode=snapshot-only' "$marker" ||
  fail "snapshot-only commissioning mode is invalid"
grep -qx 'accepted-risk=provider-snapshots' "$marker" ||
  fail "provider-snapshot risk acceptance is missing"
test ! -e /var/lib/paperclip-appliance/configured-boot-id ||
  fail "production commissioning is present or in progress"
if grep -qx 'PAPERCLIP_OFFSITE_REQUIRED=true' \
    /etc/paperclip/offsite-backup.conf 2>/dev/null; then
  fail "production offsite backup configuration is present"
fi

hermes_command=/opt/hermes-agent/$HERMES_COMMIT/venv/bin/hermes
for slug in operations research production qa; do
  home=/var/lib/paperclip/agents/$slug/home
  test "$(stat -c '%a:%U:%G' "$home/auth.json")" = 600:paperclip:paperclip ||
    fail "$slug credential ownership or mode"
  test ! -e "$home/CREDENTIAL_REQUIRED" ||
    fail "$slug credential requirement marker remains"
  status=$(/usr/sbin/runuser -u paperclip -- env -i \
    HOME=/var/lib/paperclip HERMES_HOME="$home" \
    PATH="$(dirname "$hermes_command"):/usr/bin:/bin" \
    "$hermes_command" auth status openai-codex)
  test "$status" = "openai-codex: logged in" ||
    fail "$slug OpenAI Codex credential is not locally usable"
done

company_id=$(tr -d '\n' </etc/paperclip/company-id)
agents=$(/opt/paperclip/ops/paperclip-board-api GET "/companies/$company_id/agents")
test "$(jq '[.[] | select(.adapterType=="hermes_local" and .status!="paused")]|length' \
  <<<"$agents")" -eq 4 || fail "one or more Hermes employees remain paused"

/opt/paperclip/ops/functional-acceptance.sh
current_boot=$(tr -d '\n' </proc/sys/kernel/random/boot_id)
jq -e --arg boot "$current_boot" '.pass==true and .bootId==$boot and
  .queuedObserved==true and .maxConcurrentObserved==2 and
  (.roles|length)==4 and all(.roles[];.pass==true)' \
  /var/lib/paperclip/acceptance-evidence/functional-acceptance.json >/dev/null ||
  fail "functional evidence"
echo "FUNCTIONAL ACCEPTANCE: PASS"

/opt/paperclip/ops/paperclip-secret-audit.sh >/dev/null
jq -e '.pass==true and .credentialValuesCompared>0 and .runsScanned>0 and
  .filesWithActualSecretMatches==0 and .runLogsWithActualSecretMatches==0 and
  .rawBearerOccurrences==0 and .genericTokenSignatureOccurrences==0' \
  /var/lib/paperclip/acceptance-evidence/secret-audit.json >/dev/null ||
  fail "secret audit evidence"
echo "SECRET AUDIT: PASS"

systemctl start paperclip-backup.service
/opt/paperclip/ops/paperclip-verify-encrypted-backup.sh >/dev/null
echo "LOCAL ENCRYPTED BACKUP: PASS"

failed_units=$(systemctl --failed --no-legend --plain |
  awk 'NF {count++} END {print count+0}')
test "$failed_units" -eq 0 || {
  systemctl --failed --no-pager >&2
  fail "$failed_units failed systemd unit(s)"
}
echo "SYSTEMD FAILED UNITS: 0"
echo "PRODUCTION: NOT READY (SNAPSHOT-ONLY)"
