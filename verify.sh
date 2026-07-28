#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

test "$(id -u)" -eq 0 || { echo "Run with sudo: sudo ./verify.sh" >&2; exit 77; }
mode=${1:-}
case "$mode" in ""|--platform-only) ;; *) echo "usage: sudo ./verify.sh [--platform-only]" >&2; exit 64;; esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$script_dir/appliance.lock" ]; then
  lock=$script_dir/appliance.lock
else
  lock=/opt/paperclip/integration/build/appliance.lock
fi
test -f "$lock" || { echo "FAIL: appliance.lock is missing" >&2; exit 1; }
# shellcheck disable=SC1090
. "$lock"

fail() { echo "FAIL: $*" >&2; exit 1; }
hash_is() { test "$(sha256sum "$1" | awk '{print $1}')" = "$2"; }

platform_check() {
  # shellcheck disable=SC1091
  . /etc/os-release
  test "${ID:-}" = "$SUPPORTED_UBUNTU_ID" || fail "unsupported OS"
  test "${VERSION_ID:-}" = "$SUPPORTED_UBUNTU_VERSION" || fail "Ubuntu version drift"
  test "${VERSION_CODENAME:-}" = "$SUPPORTED_UBUNTU_CODENAME" || fail "Ubuntu codename drift"
  test "$(dpkg --print-architecture)" = "$SUPPORTED_ARCH" || fail "architecture drift"
  test "$(nproc)" -ge "$MIN_CPU_COUNT" || fail "CPU capacity"
  test "$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)" -ge "$MIN_MEMORY_KIB" ||
    fail "memory capacity"
  test "$(awk 'NR>1 {total += $3} END {print total+0}' /proc/swaps)" -ge 1048576 ||
    fail "swap capacity"

  test "$(dpkg-query -W -f='${Version}' docker.io)" = "$DOCKER_PACKAGE_VERSION" ||
    fail "Docker package drift"
  test "$(dpkg-query -W -f='${Version}' containerd)" = "$CONTAINERD_PACKAGE_VERSION" ||
    fail "containerd package drift"
  test "$(dpkg-query -W -f='${Version}' runc)" = "$RUNC_PACKAGE_VERSION" ||
    fail "runc package drift"
  test "$(node --version)" = "v$NODE_VERSION" || fail "Node version drift"
  test "$(/opt/hermes-agent/$HERMES_COMMIT/venv/bin/hermes --version |
    awk 'NR==1 {sub(/^v/,"",$3); print $3; exit}')" = \
    "$HERMES_VERSION" || fail "Hermes version drift"
  test "$(node -p "require('/opt/paperclip/$PAPERCLIP_VERSION/node_modules/paperclipai/package.json').version")" = \
    "$PAPERCLIP_VERSION" || fail "Paperclip version drift"

  systemctl is-active --quiet docker.service || fail "Docker inactive"
  systemctl is-active --quiet containerd.service || fail "containerd inactive"
  systemctl is-active --quiet paperclip-network-policy.service || fail "network policy inactive"
  /opt/paperclip/ops/paperclip-network-verify >/dev/null ||
    fail "network policy rules or live probes"
  systemctl is-active --quiet paperclip.service || fail "Paperclip inactive"
  systemctl is-enabled --quiet paperclip.service || fail "Paperclip not enabled"
  for timer in paperclip-backup.timer paperclip-health.timer \
    paperclip-offsite-sync.timer paperclip-soak-sample.timer; do
    systemctl is-enabled --quiet "$timer" || fail "$timer not enabled"
    systemctl is-active --quiet "$timer" || fail "$timer not active"
  done

  docker info >/dev/null || fail "Docker daemon unavailable"
  test "$(docker image inspect --format '{{.Id}}' "$HERMES_DOCKER_IMAGE")" = \
    "$HERMES_DOCKER_IMAGE_ID" || fail "sandbox image drift"
  docker network inspect "$PAPERCLIP_NETWORK" |
    jq -e --arg subnet "$PAPERCLIP_SUBNET" --arg gateway "$PAPERCLIP_GATEWAY" \
      '.[0].Internal==false and
       .[0].Options["com.docker.network.bridge.enable_icc"]=="false" and
       .[0].IPAM.Config[0].Subnet==$subnet and
       .[0].IPAM.Config[0].Gateway==$gateway' >/dev/null ||
    fail "Docker network drift"
  jq -e '.["live-restore"]==true and
    .["log-driver"]=="json-file" and .["log-opts"]["max-size"]=="10m" and
    .["log-opts"]["max-file"]=="3"' /etc/docker/daemon.json >/dev/null ||
    fail "Docker daemon policy drift"

  curl --fail --silent --show-error --max-time 5 \
    "http://$PAPERCLIP_GATEWAY:$PAPERCLIP_PORT/api/health" |
    jq -e '.status=="ok" and .bootstrapStatus=="ready" and
      .deploymentMode=="authenticated" and .deploymentExposure=="private"' >/dev/null ||
    fail "Paperclip health or exposure"
  ss -ltnH | awk '{print $4}' | grep -qx "$PAPERCLIP_GATEWAY:$PAPERCLIP_PORT" ||
    fail "Paperclip bind address"
  if ss -ltnH | awk '{print $4}' | grep -Eq "^(0\\.0\\.0\\.0|\\*):$PAPERCLIP_PORT$"; then
    fail "Paperclip exposed on a wildcard address"
  fi
  ss -ltnH | awk '{print $4}' | grep -qx '127.0.0.1:54329' ||
    fail "embedded database bind address"

  test -f /var/lib/paperclip-appliance/complete || fail "initialization marker missing"
  test ! -e /var/lib/paperclip-appliance/pending || fail "pending initialization marker remains"
  jq -e '.secrets.strictMode==true and .auth.disableSignUp==true and
    .database.backup.enabled==false and
    .server.exposure=="private" and .server.host=="172.30.0.1"' \
    /var/lib/paperclip/instances/default/config.json >/dev/null ||
    fail "Paperclip security configuration"
  grep -qx 'PAPERCLIP_AGENT_JWT_DISABLE_LEGACY_FALLBACK=true' \
    /etc/paperclip/paperclip.env || fail "legacy JWT fallback"
  test "$(stat -c '%a:%U' /etc/paperclip/operator.env)" = "600:root" ||
    fail "operator credential permissions"
  test "$(stat -c '%a:%U' /etc/paperclip/backup-encryption.passphrase)" = "600:root" ||
    fail "backup-key permissions"

  company_id=$(tr -d '\n' </etc/paperclip/company-id)
  agents=$(/opt/paperclip/ops/paperclip-board-api GET "/companies/$company_id/agents")
  registry=/opt/paperclip/integration/factory/core-roles.tsv
  agent_ids=/etc/paperclip/hermes-agent-ids.json
  jq -e 'all(.[]; .permissions.canCreateAgents==false and
    .permissions.canCreateSkills==false)' <<<"$agents" >/dev/null ||
    fail "employee creation authority drift"
  test "$(jq 'length' "$agent_ids")" -eq 8 || fail "Core employee identity count"
  core_id_array=$(jq -c '[.[]]' "$agent_ids")
  test "$(jq --argjson ids "$core_id_array" \
    '[.[] | .id as $id |
      select(.adapterType=="hermes_local" and ($ids|index($id)))] | length' \
    <<<"$agents")" -eq 8 || fail "Core Hermes employee count"
  jq -e --argjson ids "$core_id_array" 'all(.[];
    .id as $id |
    if .adapterType=="hermes_local" and (($ids|index($id))|not)
    then .status=="paused" else true end)' <<<"$agents" >/dev/null ||
    fail "non-Core Hermes employee remains active"
  director_id=$(jq -er '.["agency-director"]' "$agent_ids")
  while IFS=$'\t' read -r slug name role title reports denied agents_sha soul_sha; do
    case "$slug" in ""|\#*) continue;; esac
    agent_id=$(jq -er --arg slug "$slug" '.[$slug]' "$agent_ids")
    agent=$(jq -c --arg id "$agent_id" '.[] | select(.id==$id)' <<<"$agents")
    test -n "$agent" || fail "missing Core employee: $slug"
    reports_id=$director_id
    test "$reports" != - || reports_id=
    can_assign=false
    test "$slug" != agency-director || can_assign=true
    jq -e --arg slug "$slug" --arg name "$name" --arg role "$role" \
      --arg title "$title" --arg cwd "/srv/paperclip/workspaces/$slug" \
      --arg home "/var/lib/paperclip/agents/$slug/home" --arg reports "$reports_id" \
      --arg command "/opt/hermes-agent/$HERMES_COMMIT/venv/bin/hermes" \
      --argjson assign "$can_assign" '
        .name==$name and .role==$role and .title==$title and
        .adapterType=="hermes_local" and .metadata.agencyOsCoreRole==true and
        .metadata.roleId==$slug and .adapterConfig.cwd==$cwd and
        .adapterConfig.env.HERMES_HOME.value==$home and
        .adapterConfig.hermesCommand==$command and
        .adapterConfig.provider=="openai-codex" and
        .adapterConfig.model=="gpt-5.6-sol" and
        .adapterConfig.paperclipApiUrl=="http://paperclip-host:3100" and
        .adapterConfig.persistSession==true and .adapterConfig.checkpoints==true and
        .adapterConfig.worktreeMode==false and
        .adapterConfig.extraArgs==["--pass-session-id"] and
        .adapterConfig.instructionsBundleMode=="managed" and
        .runtimeConfig.heartbeat.enabled==false and
        .runtimeConfig.heartbeat.maxConcurrentRuns==1 and
        .permissions.canCreateAgents==false and
        .permissions.canCreateSkills==false and
        .permissions.canAssignTasks==$assign and
        .permissions.trustPreset=="standard" and
        .permissions.authorizationPolicy.assignmentPolicy.mode=="protected" and
        (if $reports=="" then .reportsTo==null else .reportsTo==$reports end)' \
      <<<"$agent" >/dev/null || fail "Core employee configuration drift: $slug"
    test "$(cat "/var/lib/paperclip/agents/$slug/.PROFILE_READY")" = "$slug" ||
      fail "incomplete $slug profile"
    test "$(sha256sum "/srv/paperclip/workspaces/$slug/AGENTS.md" | awk '{print $1}')" = \
      "$agents_sha" || fail "$slug AGENTS.md drift"
    test "$(sha256sum "/var/lib/paperclip/agents/$slug/home/SOUL.md" | awk '{print $1}')" = \
      "$soul_sha" || fail "$slug SOUL.md drift"
    test -f "/var/lib/paperclip/agents/$slug/home/config.yaml" || fail "missing $slug profile"
  done <"$registry"

  overlay_manifest=/opt/paperclip/integration/build/locks/overlays.tsv
  test -f "$overlay_manifest" || fail "installed overlay manifest missing"
  while IFS=$'\t' read -r component _ final relative; do
    case "$component" in ""|\#*) continue ;; esac
    case "$component" in
      hermes) target="/opt/hermes-agent/$HERMES_COMMIT/$relative" ;;
      paperclip) target="/opt/paperclip/$PAPERCLIP_VERSION/$relative" ;;
      *) fail "unknown overlay component" ;;
    esac
    hash_is "$target" "$final" || fail "installed overlay drift: $relative"
  done <"$overlay_manifest"
  while IFS=$'\t' read -r expected _ destination; do
    hash_is "$destination" "$expected" ||
      fail "installed appliance asset drift: $destination"
  done </opt/paperclip/integration/build/locks/installed-assets.tsv
  /opt/paperclip/ops/paperclip-integration-regression >/dev/null ||
    fail "proprietary Hermes integration regression suite"
}

platform_check
echo "PLATFORM: PASS"
if [ "$mode" = --platform-only ]; then
  exit 0
fi

test -f /var/lib/paperclip-appliance/hermes-credential-installed ||
  fail "Hermes provider credential has not been installed"
company_id=$(tr -d '\n' </etc/paperclip/company-id)
agents=$(/opt/paperclip/ops/paperclip-board-api GET "/companies/$company_id/agents")
core_id_array=$(jq -c '[.[]]' /etc/paperclip/hermes-agent-ids.json)
test "$(jq --argjson ids "$core_id_array" \
  '[.[] | .id as $id | select(.adapterType=="hermes_local" and
    ($ids|index($id)) and .status!="paused")] | length' \
  <<<"$agents")" -eq 8 || fail "one or more Core Hermes employees remain paused"
while IFS=$'\t' read -r slug _; do
  case "$slug" in ""|\#*) continue;; esac
  test "$(stat -c '%a:%U' "/var/lib/paperclip/agents/$slug/home/auth.json")" = \
    "600:paperclip" || fail "$slug credential permissions"
done </opt/paperclip/integration/factory/core-roles.tsv
test -f /var/lib/paperclip-appliance/configured-boot-id ||
  fail "configuration boot marker is missing"
configured_boot=$(tr -d '\n' </var/lib/paperclip-appliance/configured-boot-id)
current_boot=$(tr -d '\n' </proc/sys/kernel/random/boot_id)
test "$configured_boot" != "$current_boot" ||
  fail "reboot required after configure-secrets.sh"
grep -qx 'PAPERCLIP_OFFSITE_REQUIRED=true' /etc/paperclip/offsite-backup.conf ||
  fail "required off-host backup is not configured"

/opt/paperclip/ops/functional-acceptance.sh
jq -e --arg boot "$current_boot" '.pass==true and .bootId==$boot and
  .queuedObserved==true and .maxConcurrentObserved==2 and
  (.roles|length)==8 and all(.roles[];
    .pass==true and .roleBoundaryPass==true and
    .allowedActionPass==true and .deniedRefusalPass==true and
    .noSideEffectPass==true and .inputIntegrityPass==true and
    .denialTracePass==true and .assignmentPolicyPass==true and
    (.allowedAction|length)>0 and (.deniedAction|length)>0) and
  (.runtimeBundles|length)==8 and all(.runtimeBundles[];
    .pass==true and .freshProcess==true and .soulLoadedExactly==true and
    .agentsLoadedExactly==true and .managedInstructionsExact==true)' \
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
systemctl start paperclip-offsite-sync.service
offsite_status=/var/lib/paperclip/backups/offsite-status/last-success.json
test -f "$offsite_status" || fail "off-host backup status missing"
instance_id=$(tr -d '\n' </etc/paperclip/instance-id)
latest_state=$(find /var/lib/paperclip/backups/encrypted -maxdepth 1 \
  -type f -name 'state-*.tar.gz.gpg' -printf '%T@ %f\n' |
  sort -nr | head -n 1 | cut -d' ' -f2-)
latest_database=$(find /var/lib/paperclip/backups/encrypted -maxdepth 1 \
  -type f -name 'database-*.sql.gz.gpg' -printf '%T@ %f\n' |
  sort -nr | head -n 1 | cut -d' ' -f2-)
jq -e --arg instance "$instance_id" --arg state "$latest_state" \
  --arg database "$latest_database" \
  '.verified==true and .instanceId==$instance and
   .latestState==$state and .latestDatabase==$database and
   .recoveryKeyEscrowed==true and
   (.mountSource|length)>0 and (.mountType|length)>0 and
   (.escrowSource|length)>0 and (.escrowType|length)>0 and
   .mountSource != .escrowSource' "$offsite_status" >/dev/null ||
  fail "off-host backup does not match the latest encrypted backup"
echo "BACKUP: PASS"

failed_units=$(systemctl --failed --no-legend --plain | awk 'NF {count++} END {print count+0}')
test "$failed_units" -eq 0 || {
  systemctl --failed --no-pager >&2
  fail "$failed_units failed systemd unit(s)"
}
echo "SYSTEMD FAILED UNITS: 0"
echo "PRODUCTION: READY"
