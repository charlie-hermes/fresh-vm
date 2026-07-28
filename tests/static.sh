#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$repo/appliance.lock"
cd "$repo"

test -f MANIFEST.sha256
sha256sum --check --strict MANIFEST.sha256 >/dev/null
test "$(tests/generate-manifest.sh)" = "$(cat MANIFEST.sha256)"

for script in bootstrap.sh configure-secrets.sh verify.sh scripts/* \
  files/factory/skills/paperclip-employee/scripts/* tests/*.sh; do
  case "$script" in *.md) continue ;; esac
  bash -n "$script"
done
for script in files/ops/*; do
  case "$(head -n 1 "$script")" in
    *bash*) bash -n "$script" ;;
    *sh*) sh -n "$script" ;;
  esac
done

jq -e . files/docker/daemon.json files/paperclip/config.json \
  locks/paperclip/package.json locks/paperclip/package-lock.json >/dev/null
test "$(sha256sum locks/paperclip/package-lock.json | awk '{print $1}')" = \
  "$PAPERCLIP_PACKAGE_LOCK_SHA256"
test "$(node -p "require('./locks/paperclip/package-lock.json').packages['node_modules/paperclipai'].integrity")" = \
  "$PAPERCLIP_PACKAGE_INTEGRITY"
test "$(files/bin/jq --version)" = "jq-$JQ_VERSION"
test "$(sha256sum files/bin/jq | awk '{print $1}')" = "$JQ_SHA256"

registry=files/factory/core-roles.tsv
test "$(awk -F '\t' '$1 !~ /^#/ && NF {n++} END {print n+0}' "$registry")" -eq 8
test "$(awk -F '\t' '$1 !~ /^#/ && NF {print $1}' "$registry" | sort -u | wc -l)" -eq 8
test "$(awk -F '\t' '$1 !~ /^#/ && NF && $5=="-" {print $1}' "$registry")" =   agency-director
while IFS=$'\t' read -r slug _ role _ reports denied agents_sha soul_sha; do
  case "$slug" in ""|\#*) continue;; esac
  case "$role" in ceo|pm|researcher|designer|qa|devops) ;; *) exit 1;; esac
  case "$reports" in -|agency-director) ;; *) exit 1;; esac
  test "$(sha256sum "files/factory/core-roles/$slug/AGENTS.md" | awk '{print $1}')" =     "$agents_sha"
  test "$(sha256sum "files/factory/core-roles/$slug/SOUL.md" | awk '{print $1}')" =     "$soul_sha"
  IFS=, read -r -a denied_list <<<"$denied"
  test "${#denied_list[@]}" -gt 0
  for tool in "${denied_list[@]}"; do
    grep -qx "    - $tool" files/factory/config.yaml.template
  done
done <"$registry"

for field in allowedActionPass deniedRefusalPass noSideEffectPass \
  inputIntegrityPass denialTracePass assignmentPolicyPass roleBoundaryPass; do
  grep -q "$field" scripts/functional-acceptance.sh
  grep -q "$field" verify.sh
done
grep -q "trap 'restore_transition 129' HUP" scripts/core-role-transition
grep -q "trap 'restore_transition 130' INT" scripts/core-role-transition
grep -q "trap 'restore_transition 143' TERM" scripts/core-role-transition
grep -q "runId // .id" scripts/functional-acceptance.sh
grep -q "paperclip-http-denial-check" scripts/functional-acceptance.sh
grep -q 'web-search-log "$hermes_session"' scripts/functional-acceptance.sh
grep -q 'assignmentPolicy:{mode:"protected"}' scripts/core-role-transition
grep -q 'permissions.authorizationPolicy.assignmentPolicy.mode=="protected"' verify.sh
grep -q 'already_active' scripts/core-role-transition
grep -q 'activation_mode=reconcile' scripts/core-role-transition
grep -q '^    validate_current_core_credentials$' scripts/core-role-transition
grep -q '^    snapshot_reconcile_agents$' scripts/core-role-transition
grep -q '^  arm_transition "$activation_mode"$' scripts/core-role-transition
grep -q '^  if test "$already_active" = false; then$' scripts/core-role-transition
snapshot_line=$(grep -n '^    snapshot_reconcile_agents$' scripts/core-role-transition | cut -d: -f1)
arm_line=$(grep -n '^  arm_transition "$activation_mode"$' scripts/core-role-transition | cut -d: -f1)
mutation_line=$(grep -n '^  create_or_update_core_agents$' scripts/core-role-transition | cut -d: -f1)
test "$snapshot_line" -lt "$arm_line" && test "$arm_line" -lt "$mutation_line"
! grep -q 'already active and platform verification passed' scripts/core-role-transition

while IFS=$'\t' read -r component _ final relative; do
  case "$component" in ""|\#*) continue ;; esac
  target="overlays/$component/$relative"
  test -f "$target"
  test "$(sha256sum "$target" | awk '{print $1}')" = "$final"
done <locks/overlays.tsv

while IFS=$'\t' read -r expected source destination; do
  test -f "$source"
  test "${destination#/}" != "$destination"
  test "$(sha256sum "$source" | awk '{print $1}')" = "$expected"
done <locks/installed-assets.tsv
test "$(tests/generate-installed-assets.sh)" = "$(cat locks/installed-assets.tsv)"
./tests/tool-completion.sh >/dev/null
./tests/http-denial-evidence.sh >/dev/null
./tests/core-transition.sh >/dev/null

if git ls-files --others --cached --exclude-standard 2>/dev/null |
   grep -E '(^|/)(auth\.json|\.env|hermes\.env|offsite-backup\.conf)$' >/dev/null; then
  echo "Secret-bearing filename found in repository" >&2
  exit 1
fi
if rg -n --hidden --glob '!.git/**' --glob '!tests/static.sh' -- \
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9_.-]{12,}' .; then
  echo "Credential-like content found in repository" >&2
  exit 1
fi

echo "STATIC VALIDATION PASS"
