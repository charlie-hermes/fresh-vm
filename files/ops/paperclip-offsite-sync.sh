#!/bin/sh
set -eu

config=/etc/paperclip/offsite-backup.conf
test -r "$config" || { echo "Missing $config" >&2; exit 1; }
# shellcheck disable=SC1090
. "$config"

: "${PAPERCLIP_OFFSITE_MOUNT:=/mnt/paperclip-offsite}"
: "${PAPERCLIP_OFFSITE_REQUIRED:=false}"
instance_id=$(cat /etc/paperclip/instance-id)
source_dir=/var/lib/paperclip/backups/encrypted
target_dir=$PAPERCLIP_OFFSITE_MOUNT/paperclip/$instance_id/encrypted

if ! /usr/bin/mountpoint -q "$PAPERCLIP_OFFSITE_MOUNT"; then
  if [ "$PAPERCLIP_OFFSITE_REQUIRED" = true ]; then
    echo "Required off-host backup mount is unavailable: $PAPERCLIP_OFFSITE_MOUNT" >&2
    exit 1
  fi
  echo "Off-host backup is prepared but not configured; mount $PAPERCLIP_OFFSITE_MOUNT and set PAPERCLIP_OFFSITE_REQUIRED=true"
  exit 0
fi

mkdir -p "$target_dir"
test -w "$target_dir" || { echo "Off-host target is not writable: $target_dir" >&2; exit 1; }

find "$source_dir" -maxdepth 1 -type f \( -name '*.gpg' -o -name '*.gpg.sha256' \) -print |
while IFS= read -r source; do
  name=$(basename "$source")
  target=$target_dir/$name
  if [ ! -e "$target" ]; then
    temp=$target.partial.$$
    cp --preserve=timestamps "$source" "$temp"
    chmod 0640 "$temp"
    mv "$temp" "$target"
  fi
done

for checksum in "$target_dir"/*.gpg.sha256; do
  test -e "$checksum" || continue
  name=$(basename "$checksum")
  artifact=${name%.sha256}
  expected=$(awk '{print $1}' "$checksum")
  actual=$(sha256sum "$target_dir/$artifact" | awk '{print $1}')
  test "$expected" = "$actual" || { echo "Off-host checksum mismatch: $artifact" >&2; exit 1; }
done

latest_state=$(find "$target_dir" -maxdepth 1 -type f -name 'state-*.tar.gz.gpg' -printf '%T@ %f\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
latest_database=$(find "$target_dir" -maxdepth 1 -type f -name 'database-*.sql.gz.gpg' -printf '%T@ %f\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
test -n "$latest_state" && test -n "$latest_database"

status_dir=/var/lib/paperclip/backups/offsite-status
mkdir -p "$status_dir"
jq -nc --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg mount "$PAPERCLIP_OFFSITE_MOUNT" \
  --arg instanceId "$instance_id" --arg state "$latest_state" --arg database "$latest_database" \
  '{timestamp:$timestamp,mount:$mount,instanceId:$instanceId,latestState:$state,latestDatabase:$database,verified:true}' \
  >"$status_dir/last-success.json"
chmod 0640 "$status_dir/last-success.json"
echo "Encrypted off-host backup sync verified for instance $instance_id"
