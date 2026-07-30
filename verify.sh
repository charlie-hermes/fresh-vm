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

verification_lines=()
verification_started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
verification_result=/var/lib/paperclip-appliance/verification-result.json
g2_result=null
g2_result_checksum=
brand_agent_result=null
brand_agent_result_checksum=
required_lines='["PLATFORM: PASS","FUNCTIONAL ACCEPTANCE: PASS","AGENCY OS: LIVE","SECRET AUDIT: PASS","SYSTEMD FAILED UNITS: 0","PRODUCTION: READY"]'
write_verification_evidence() {
  exit_status=$?
  trap - EXIT
  if [ "$mode" = --platform-only ]; then
    exit "$exit_status"
  fi
  if [ "${#verification_lines[@]}" -eq 0 ]; then
    output_lines='[]'
  else
    output_lines=$(printf '%s\n' "${verification_lines[@]}" | jq -Rsc 'split("\n")[:-1]')
  fi
  status=failed
  if [ "$exit_status" -eq 0 ] &&
     jq -en --argjson output "$output_lines" --argjson required "$required_lines" \
       '$output==$required' >/dev/null; then
    status=pass
  fi
  verifier_sha256=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')
  lock_sha256=$(sha256sum "$lock" | awk '{print $1}')
  assets_sha256=$(sha256sum /opt/paperclip/integration/build/locks/installed-assets.tsv 2>/dev/null | awk '{print $1}')
  boot_id=$(tr -d '\n' </proc/sys/kernel/random/boot_id)
  temporary=$(mktemp /var/lib/paperclip-appliance/.verification-result.XXXXXX)
  jq -n \
    --arg schema_version "1.0" --arg status "$status" \
    --arg started_at "$verification_started_at" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg boot_id "$boot_id" --arg agency_os_commit "$AGENCY_OS_COMMIT" \
    --arg verifier_sha256 "$verifier_sha256" --arg appliance_lock_sha256 "$lock_sha256" \
    --arg installed_assets_sha256 "$assets_sha256" \
    --arg g2_result_checksum "$g2_result_checksum" \
    --arg brand_agent_result_checksum "$brand_agent_result_checksum" \
    --argjson exit_status "$exit_status" --argjson output_lines "$output_lines" \
    --argjson required_lines "$required_lines" --argjson g2_summary "$g2_result" \
    --argjson brand_agent_summary "$brand_agent_result" \
    '{schema_version:$schema_version,status:$status,exit_status:$exit_status,
      started_at:$started_at,completed_at:$completed_at,boot_id:$boot_id,
      output_lines:$output_lines,required_lines:$required_lines,
      agency_os_commit:$agency_os_commit,verifier_sha256:$verifier_sha256,
      appliance_lock_sha256:$appliance_lock_sha256,
      installed_assets_sha256:$installed_assets_sha256,
      g2_result_checksum:$g2_result_checksum,g2_summary:$g2_summary,
      brand_agent_result_checksum:$brand_agent_result_checksum,
      brand_agent_summary:$brand_agent_summary}' >"$temporary"
  chmod 0600 "$temporary"
  chown root:root "$temporary"
  mv -f "$temporary" "$verification_result"
  exit "$exit_status"
}
trap write_verification_evidence EXIT

gate_pass() {
  verification_lines+=("$1")
  printf '%s\n' "$1"
}
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
  test "$(dpkg-query -W -f='${Version}' python3-jsonschema)" = \
    "$PYTHON_JSONSCHEMA_PACKAGE_VERSION" || fail "jsonschema package drift"
  test "$(dpkg-query -W -f='${Version}' clamav)" = "$CLAMAV_PACKAGE_VERSION" ||
    fail "ClamAV package drift"
  test "$(dpkg-query -W -f='${Version}' poppler-utils)" = "$POPPLER_UTILS_PACKAGE_VERSION" ||
    fail "Poppler package drift"
  test "$(dpkg-query -W -f='${Version}' tesseract-ocr)" = "$TESSERACT_OCR_PACKAGE_VERSION" ||
    fail "Tesseract package drift"
  for package in clamav poppler-utils tesseract-ocr; do
    apt-mark showhold | grep -qx "$package" || fail "$package is not held at its appliance pin"
  done
  systemctl is-active --quiet clamav-freshclam.service || fail "ClamAV signature updater inactive"
  signature=$(find /var/lib/clamav -maxdepth 1 -type f \
    \( -name 'daily.cvd' -o -name 'daily.cld' -o -name 'main.cvd' -o -name 'main.cld' \) \
    -mmin -2880 -print -quit)
  test -n "$signature" || fail "ClamAV signatures are absent or stale"
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
  for service in fleet-portal-authority.service fleet-portal-command-worker.service \
    fleet-ingest-worker.service fleet-portal-web.service; do
    systemctl is-enabled --quiet "$service" || fail "$service not enabled"
    systemctl is-active --quiet "$service" || fail "$service not active"
  done
  for timer in paperclip-health.timer paperclip-soak-sample.timer; do
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
  ss -ltnH | awk '{print $4}' | grep -qx '127.0.0.1:3190' ||
    fail "Fleet portal loopback bind address"
  if ss -ltnH | awk '{print $4}' | grep -Eq '^(0\.0\.0\.0|\*):3190$'; then
    fail "Fleet portal exposed on a wildcard address"
  fi
  curl --fail --silent --max-time 5 http://127.0.0.1:3190/health |
    jq -e '.status=="pass" and .service=="fleet-portal-web" and
      .authority=="fleet_portal"' >/dev/null || fail "Fleet portal authority health"
  test "$(stat -c '%a:%U' /etc/agency-os/fleet-portal.env)" = "600:root" ||
    fail "Fleet portal credential permissions"
  for database in fleet-tenancy.sqlite3 fleet-brand-intelligence.sqlite3 fleet-portal.sqlite3; do
    test "$(stat -c '%a:%U:%G' "/var/lib/agency-os/$database")" =       "600:fleet-authority:fleet-authority" || fail "Fleet authority database permissions: $database"
  done
  test -S /run/agency-os/fleet-authority.sock || fail "Fleet authority socket"
  test "$(systemctl show -p User --value fleet-portal-web.service)" = fleet-portal ||
    fail "Fleet portal web service identity"
  test "$(systemctl show -p User --value fleet-portal-authority.service)" = fleet-authority ||
    fail "Fleet authority service identity"
  test "$(systemctl show -p User --value fleet-portal-command-worker.service)" = fleet-command ||
    fail "Fleet command worker service identity"
  systemctl cat fleet-portal-command-worker.service | grep -qx 'IPAddressDeny=any' ||
    fail "Fleet command worker egress deny policy"
  systemctl cat fleet-portal-command-worker.service | grep -qx 'IPAddressAllow=172.30.0.1' ||
    fail "Fleet command worker Paperclip-only egress policy"
  ! systemctl show -p EnvironmentFiles --value fleet-portal-command-worker.service |     grep -q '/etc/paperclip/operator.env' ||
    fail "Fleet command worker still receives operator credentials"
  test "$(stat -c '%a:%U:%G' /etc/agency-os/fleet-command-paperclip.env)" = "640:root:fleet-command" ||
    fail "Fleet command-worker credential permissions"
  operator_token=$(awk -F= '$1=="PAPERCLIP_BOARD_API_KEY" {print $2}' /etc/paperclip/operator.env)
  worker_token=$(awk -F= '$1=="PAPERCLIP_BOARD_TOKEN" {print $2}' /etc/agency-os/fleet-command-paperclip.env)
  test -n "$operator_token" && test -n "$worker_token" && test "$operator_token" != "$worker_token" ||
    fail "Fleet command worker does not have a distinct Paperclip credential"
  unset operator_token worker_token
  sudo -u fleet-authority test ! -r /etc/agency-os/fleet-command-paperclip.env ||
    fail "Fleet authority can read the command-worker credential"
  id -nG fleet-command | tr ' ' '\n' | grep -qx fleet-authority-client ||
    fail "Fleet command worker lacks authority-socket group"
  ! id -nG fleet-authority | tr ' ' '\n' | grep -qx fleet-command ||
    fail "Fleet authority retains command-credential group access"
  systemctl show -p SupplementaryGroups --value fleet-portal-web.service |
    grep -qw fleet-ingest || fail "Fleet portal ingest boundary"
  test "$(systemctl show -p PrivateNetwork --value fleet-ingest-worker.service)" = yes ||
    fail "Fleet ingest network isolation"
  ! systemctl show -p Environment --value fleet-portal-web.service |
    grep -q 'PAPERCLIP_' || fail "Paperclip credential leaked to Fleet web service"
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
  /usr/local/sbin/fleet-portal-paperclip-sync --verify-only >/dev/null ||
    fail "Fleet G2.6 Paperclip task graph"
  /usr/local/sbin/fleet-portal-external-verify >/dev/null ||
    fail "Fleet portal external WorkOS and Cloudflare commissioning"

  company_id=$(tr -d '\n' </etc/paperclip/company-id)
  agents=$(/opt/paperclip/ops/paperclip-board-api GET "/companies/$company_id/agents")
  registry=/opt/paperclip/integration/factory/core-roles.tsv
  agent_ids=/etc/paperclip/hermes-agent-ids.json
  jq -e 'all(.[]; .permissions.canCreateAgents==false and
    .permissions.canCreateSkills==false)' <<<"$agents" >/dev/null ||
    fail "employee creation authority drift"
  test "$(jq 'length' "$agent_ids")" -eq 12 || fail "Agency employee identity count"
  core_id_array=$(jq -c '[.[]]' "$agent_ids")
  test "$(jq --argjson ids "$core_id_array" \
    '[.[] | .id as $id |
      select(.adapterType=="hermes_local" and ($ids|index($id)))] | length' \
    <<<"$agents")" -eq 12 || fail "Agency Hermes employee count"
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
gate_pass "PLATFORM: PASS"
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
  <<<"$agents")" -eq 12 || fail "one or more Agency Hermes employees remain paused"
while IFS=$'\t' read -r slug _; do
  case "$slug" in ""|\#*) continue;; esac
  test "$(stat -c '%a:%U' "/var/lib/paperclip/agents/$slug/home/auth.json")" = \
    "600:paperclip" || fail "$slug credential permissions"
done </opt/paperclip/integration/factory/core-roles.tsv
current_boot=$(tr -d '\n' </proc/sys/kernel/random/boot_id)

/opt/paperclip/ops/functional-acceptance.sh
jq -e --arg boot "$current_boot" '.pass==true and .bootId==$boot and
  .queuedObserved==true and .maxConcurrentObserved==2 and
  (.roles|length)==12 and all(.roles[];
    .pass==true and .roleBoundaryPass==true and
    .allowedActionPass==true and .deniedRefusalPass==true and
    .noSideEffectPass==true and .inputIntegrityPass==true and
    .denialTracePass==true and .assignmentPolicyPass==true and
    (.allowedAction|length)>0 and (.deniedAction|length)>0) and
  (.runtimeBundles|length)==12 and all(.runtimeBundles[];
    .pass==true and .freshProcess==true and .soulLoadedExactly==true and
    .agentsLoadedExactly==true and .managedInstructionsExact==true)' \
  /var/lib/paperclip/acceptance-evidence/functional-acceptance.json >/dev/null ||
  fail "functional evidence"
gate_pass "FUNCTIONAL ACCEPTANCE: PASS"

test "$(git -C /opt/agency-os/current rev-parse HEAD)" = "$AGENCY_OS_COMMIT" ||
  fail "Agency OS release drift"
hash_is /usr/local/bin/buzz "$AGENCY_OS_BUZZ_SHA256" ||
  fail "Buzz binary drift"
systemctl is-enabled --quiet agency-os-operator.service ||
  fail "Agency OS operator portal is not enabled"
systemctl is-active --quiet agency-os-operator.service ||
  fail "Agency OS operator portal is not active"
buzz_uid=$(id -u ubuntu)
runuser -u ubuntu -- env XDG_RUNTIME_DIR="/run/user/$buzz_uid" \
  systemctl --user is-active --quiet buzz-codex-bridge.service ||
  fail "Buzz bridge is not active"
ss -ltnH | awk '{print $4}' | grep -qx '127.0.0.1:3180' ||
  fail "Agency OS operator portal bind address"
evidence=/var/lib/paperclip-appliance/agency-os-production.json
test "$(stat -c '%a:%U' "$evidence")" = "600:root" ||
  fail "Agency OS production evidence permissions"
jq -e --arg commit "$AGENCY_OS_COMMIT" \
  '.schema_version=="1.0" and .status=="live_production" and
   .agency_os_commit==$commit and .brand_id=="brand_agency_live" and
   .paperclip_authenticated==true and .buzz_authenticated==true and
   .provider_external_writes==false and .mock_publication_calls==3 and
   .core.task_count==8 and .core.approval_status=="approved" and
   (.core.buzz_channel_id|length)>0 and
   .core.paperclip_cost_event_recorded==true and
   .social.task_count==5 and .social.approval_status=="approved" and
   (.social.buzz_channel_id|length)>0 and
   .isolation_brand.task_count==8 and
   .isolation_brand.approval_status=="approved" and
   .isolation_brand.cross_brand_social_denied==true and
   .isolation_brand.denial_created_tasks==false and
   .isolation_brand.paperclip_cost_event_recorded==false' "$evidence" >/dev/null ||
  fail "Agency OS live workflow evidence"
g2_result=$(/opt/paperclip/ops/agency-os-g2-verify) || fail "Fleet G2 live foundation"
g2_result_checksum=$(printf '%s' "$g2_result" | sha256sum | awk '{print $1}')
brand_agent_result=$(/opt/paperclip/ops/agency-os-brand-agent-verify) ||
  fail "Fleet Brand Agent G2.5"
brand_agent_result_checksum=$(printf '%s' "$brand_agent_result" | sha256sum | awk '{print $1}')
portal=$(curl --fail --silent --show-error --max-time 5 \
  http://127.0.0.1:3180/api/status) || fail "Agency OS operator portal health"
jq -e '.authority=="paperclip" and .projection=="read_only" and
  .admin.role_bundle_count==12 and .portfolio.brand_count==2 and
  (.portfolio.campaign_count>=3) and (.approvals|length)==3' \
  <<<"$portal" >/dev/null ||
  fail "Agency OS operator portal evidence"
gate_pass "AGENCY OS: LIVE"

/opt/paperclip/ops/paperclip-secret-audit.sh >/dev/null
jq -e '.pass==true and .credentialValuesCompared>0 and .runsScanned>0 and
  .filesWithActualSecretMatches==0 and .runLogsWithActualSecretMatches==0 and
  .rawBearerOccurrences==0 and .genericTokenSignatureOccurrences==0' \
  /var/lib/paperclip/acceptance-evidence/secret-audit.json >/dev/null ||
  fail "secret audit evidence"
gate_pass "SECRET AUDIT: PASS"

failed_units=$(systemctl --failed --no-legend --plain | awk 'NF {count++} END {print count+0}')
test "$failed_units" -eq 0 || {
  systemctl --failed --no-pager >&2
  fail "$failed_units failed systemd unit(s)"
}
gate_pass "SYSTEMD FAILED UNITS: 0"
gate_pass "PRODUCTION: READY"
