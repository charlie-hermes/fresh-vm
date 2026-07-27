#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

test "$(id -u)" -eq 0 || {
  echo "Run with sudo: sudo ./configure-secrets.sh AUTH_JSON OFFSITE_CONFIG" >&2
  exit 77
}
auth_source=${1:-}
offsite_source=${2:-}
test "$#" -eq 2 || {
  echo "usage: sudo ./configure-secrets.sh AUTH_JSON OFFSITE_CONFIG" >&2
  exit 64
}
for source in "$auth_source" "$offsite_source"; do
  test -f "$source" && test ! -L "$source" ||
    { echo "Input must be a regular, non-symlink file: $source" >&2; exit 64; }
done
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

if grep -Ev '^[[:space:]]*(#.*)?$|^PAPERCLIP_OFFSITE_REQUIRED=true$|^PAPERCLIP_OFFSITE_MOUNT=/[A-Za-z0-9._/-]+$|^PAPERCLIP_RECOVERY_ESCROW_MOUNT=/[A-Za-z0-9._/-]+$' \
    "$offsite_source" | grep -q .; then
  echo "OFFSITE_CONFIG contains unsupported or unsafe syntax" >&2
  exit 65
fi
test "$(grep -cx 'PAPERCLIP_OFFSITE_REQUIRED=true' "$offsite_source" || true)" -eq 1 ||
  { echo "OFFSITE_CONFIG must set PAPERCLIP_OFFSITE_REQUIRED=true" >&2; exit 65; }
test "$(grep -c '^PAPERCLIP_OFFSITE_MOUNT=' "$offsite_source" || true)" -eq 1 ||
  { echo "OFFSITE_CONFIG must set PAPERCLIP_OFFSITE_MOUNT exactly once" >&2; exit 65; }
test "$(grep -c '^PAPERCLIP_RECOVERY_ESCROW_MOUNT=' "$offsite_source" || true)" -eq 1 ||
  { echo "OFFSITE_CONFIG must set PAPERCLIP_RECOVERY_ESCROW_MOUNT exactly once" >&2; exit 65; }
offsite_mount=$(sed -n 's/^PAPERCLIP_OFFSITE_MOUNT=//p' "$offsite_source" | tail -n 1)
escrow_mount=$(sed -n 's/^PAPERCLIP_RECOVERY_ESCROW_MOUNT=//p' "$offsite_source" | tail -n 1)
test "$offsite_mount" != "$escrow_mount" ||
  { echo "Backup and recovery-key escrow must use different mounts" >&2; exit 65; }
offsite_identity=$(/opt/paperclip/ops/paperclip-validate-remote-mount "$offsite_mount")
escrow_identity=$(/opt/paperclip/ops/paperclip-validate-remote-mount "$escrow_mount")
test "$(printf '%s' "$offsite_identity" | cut -f2)" != \
     "$(printf '%s' "$escrow_identity" | cut -f2)" ||
  { echo "Backup and recovery-key escrow must use different remote sources" >&2; exit 65; }
test -d "$offsite_mount" && test -w "$offsite_mount" ||
  { echo "Off-host destination is not writable: $offsite_mount" >&2; exit 69; }
test -d "$escrow_mount" && test -w "$escrow_mount" ||
  { echo "Recovery-key escrow is not writable: $escrow_mount" >&2; exit 69; }

install -o root -g paperclip -m 0640 "$offsite_source" \
  /etc/paperclip/offsite-backup.conf
/usr/local/sbin/paperclip-hermes-credential-install "$auth_source"
tr -d '\n' </proc/sys/kernel/random/boot_id \
  >/var/lib/paperclip-appliance/configured-boot-id
chmod 0600 /var/lib/paperclip-appliance/configured-boot-id
systemctl start paperclip-backup.service
systemctl start paperclip-offsite-sync.service
systemctl enable --now \
  paperclip-backup.timer paperclip-health.timer \
  paperclip-offsite-sync.timer paperclip-soak-sample.timer >/dev/null
rm -f -- /var/lib/paperclip-appliance/snapshot-only-commissioned

echo "Provider credential installed into four isolated profiles."
echo "Required encrypted off-host backup completed and verified."
echo "Reboot now: sudo reboot"
