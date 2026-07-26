#!/bin/sh
set -u

sample_dir=/var/lib/paperclip/soak
sample_file=$sample_dir/samples.jsonl
mkdir -p "$sample_dir"
chmod 0750 "$sample_dir"

health=pass
health_detail='Paperclip health checks passed'
if ! health_output=$(/opt/paperclip/ops/paperclip-health.sh 2>&1); then
  health=fail
  health_detail=$health_output
fi

api_status=unknown
if api_json=$(mktemp); then
  if /usr/bin/curl --fail --silent --show-error --max-time 5 http://172.30.0.1:3100/api/health >"$api_json"; then
    api_status=$(/usr/bin/jq -r '.status // "unknown"' "$api_json")
  fi
  rm -f "$api_json"
fi

paperclip_active=$(/usr/bin/systemctl is-active paperclip.service 2>/dev/null || true)
docker_active=$(/usr/bin/systemctl is-active docker.service 2>/dev/null || true)
network_active=$(/usr/bin/systemctl is-active paperclip-network-policy.service 2>/dev/null || true)
disk_percent=$(/usr/bin/df -P /var/lib/paperclip | /usr/bin/awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
memory_available_kib=$(/usr/bin/awk '/MemAvailable:/ { print $2 }' /proc/meminfo)
swap_free_kib=$(/usr/bin/awk '/SwapFree:/ { print $2 }' /proc/meminfo)
hermes_containers=$(/usr/bin/docker ps --filter label=hermes-agent=1 --format '{{.ID}}' 2>/dev/null | /usr/bin/wc -l)
latest_backup_epoch=$(/usr/bin/find /var/lib/paperclip/backups/encrypted -maxdepth 1 -type f -name 'state-*.tar.gz.gpg' -printf '%T@\n' 2>/dev/null | /usr/bin/sort -nr | /usr/bin/head -n 1 | /usr/bin/cut -d. -f1)
latest_backup_epoch=${latest_backup_epoch:-0}

/usr/bin/jq -nc \
  --arg timestamp "$(/usr/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg health "$health" --arg healthDetail "$health_detail" --arg apiStatus "$api_status" \
  --arg paperclip "$paperclip_active" --arg docker "$docker_active" --arg network "$network_active" \
  --argjson diskPercent "$disk_percent" --argjson memoryAvailableKiB "$memory_available_kib" \
  --argjson swapFreeKiB "$swap_free_kib" --argjson hermesContainers "$hermes_containers" \
  --argjson latestBackupEpoch "$latest_backup_epoch" \
  '{timestamp:$timestamp,health:$health,healthDetail:$healthDetail,apiStatus:$apiStatus,services:{paperclip:$paperclip,docker:$docker,networkPolicy:$network},resources:{diskPercent:$diskPercent,memoryAvailableKiB:$memoryAvailableKiB,swapFreeKiB:$swapFreeKiB,hermesContainers:$hermesContainers},latestEncryptedStateBackupEpoch:$latestBackupEpoch}' \
  >>"$sample_file"
chmod 0640 "$sample_file"

printf 'Paperclip soak sample recorded: %s\n' "$health"
test "$health" = pass
