#!/bin/sh
set -eu

health_json=$(mktemp)
network_json=$(mktemp)
trap 'rm -f "$health_json" "$network_json"' EXIT HUP INT TERM

/usr/bin/curl --fail --silent --show-error --max-time 5 http://172.30.0.1:3100/api/health >"$health_json"
/usr/bin/jq -e '.status == "ok" and .bootstrapStatus == "ready" and .deploymentMode == "authenticated" and .deploymentExposure == "private"' "$health_json" >/dev/null

/usr/bin/docker network inspect paperclip-hermes >"$network_json"
/usr/bin/jq -e '.[0].Internal == false and .[0].Options["com.docker.network.bridge.enable_icc"] == "false" and .[0].IPAM.Config[0].Subnet == "172.30.0.0/24"' "$network_json" >/dev/null
/usr/bin/systemctl is-active --quiet paperclip-network-policy.service

used_percent=$(/usr/bin/df -P /var/lib/paperclip | /usr/bin/awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
if [ "$used_percent" -ge 85 ]; then
  echo "Paperclip disk usage is ${used_percent}% (threshold: 85%)" >&2
  exit 1
fi

swap_kib=$(/usr/bin/awk 'NR > 1 { total += $3 } END { print total + 0 }' /proc/swaps)
if [ "$swap_kib" -lt 1048576 ]; then
  echo "Paperclip host swap is below 1 GiB" >&2
  exit 1
fi

/usr/bin/jq -e '.secrets.strictMode == true and .auth.disableSignUp == true' /var/lib/paperclip/instances/default/config.json >/dev/null
/usr/bin/grep -qx 'PAPERCLIP_AGENT_JWT_DISABLE_LEGACY_FALLBACK=true' /etc/paperclip/paperclip.env
/usr/bin/grep -qx 'PAPERCLIP_HEARTBEAT_GLOBAL_MAX_CONCURRENT_RUNS=2' /etc/paperclip/paperclip.env

echo "Paperclip health PASS; disk ${used_percent}%; swap ${swap_kib} KiB"
