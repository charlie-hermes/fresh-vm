#!/bin/bash
set -euo pipefail

test "$(id -u)" -eq 0 || { echo "must run as root" >&2; exit 77; }
work=$(mktemp -d)
chmod 0700 "$work"
trap 'rm -rf "$work"' EXIT HUP INT TERM
raw=$work/secrets.raw
secrets=$work/secrets
: >"$raw"
chmod 0600 "$raw"

while IFS= read -r env_file; do
  awk -F= '$0 !~ /^[[:space:]]*#/ && toupper($1) ~ /(TOKEN|SECRET|KEY|PASSWORD|COOKIE)/ {
    value=substr($0,index($0,"=")+1)
    gsub(/^['\''"]|['\''"]$/, "", value)
    if (length(value) >= 12) print value
  }' "$env_file" >>"$raw"
done < <(find /etc/paperclip /var/lib/paperclip/agents -type f \( -name '*.env' -o -name '.env' \) 2>/dev/null)

while IFS= read -r json_file; do
  jq -r 'paths(scalars) as $p
    | select(($p[-1] | tostring | test("^(access_token|refresh_token|id_token|token|api_key|secret|password|cookie|key)$"; "i")))
    | getpath($p)
    | select(type == "string" and length >= 12)' "$json_file" 2>/dev/null >>"$raw" || true
done < <(find /var/lib/paperclip/agents -type f -name 'auth.json' 2>/dev/null)

for secret_file in \
  /etc/paperclip/backup-encryption.passphrase \
  /var/lib/paperclip/instances/default/secrets/master.key; do
  if test -f "$secret_file"; then
    awk 'length($0) >= 12 {print}' "$secret_file" >>"$raw"
  fi
done

sort -u "$raw" >"$secrets"
chmod 0600 "$secrets"
secret_count=$(wc -l <"$secrets")
test "$secret_count" -gt 0 || { echo "No credential values found for comparison" >&2; exit 1; }

file_matches=$work/file-matches
: >"$file_matches"
for root in \
  /opt/paperclip/integration \
  /srv/paperclip/workspaces \
  /var/lib/paperclip/acceptance-evidence \
  /var/lib/paperclip/instances/default/data \
  /var/lib/paperclip/instances/default/logs \
  /var/lib/paperclip/agents; do
  test -e "$root" || continue
  grep -RIlFf "$secrets" "$root" \
    --exclude='*.gpg' --exclude='*.gz' --exclude='*.sha256' --exclude='*.sqlite*' \
    --exclude='auth.json' --exclude='.env' \
    --exclude-dir=backups --exclude-dir=db 2>/dev/null >>"$file_matches" || true
done
sort -u -o "$file_matches" "$file_matches"

runs_scanned=0
secret_log_matches=0
raw_bearer_occurrences=0
run_ids=$work/run-ids
: >"$run_ids"
while IFS= read -r company; do
  while IFS= read -r agent_id; do
    /opt/paperclip/ops/paperclip-board-api GET "/companies/$company/heartbeat-runs?agentId=$agent_id&limit=30" \
      | jq -r '.[].id' >>"$run_ids"
  done < <(/opt/paperclip/ops/paperclip-board-api GET "/companies/$company/agents" | jq -r '.[].id')
done < <(/opt/paperclip/ops/paperclip-board-api GET /companies | jq -r '.[].id')
sort -u -o "$run_ids" "$run_ids"

while IFS= read -r run_id; do
  log_file=$work/log-$run_id
  if /opt/paperclip/ops/paperclip-board-api GET "/heartbeat-runs/$run_id/log" \
    | jq -r '.content // ""' >"$log_file" 2>/dev/null; then
    runs_scanned=$((runs_scanned + 1))
    if grep -Fqf "$secrets" "$log_file"; then
      secret_log_matches=$((secret_log_matches + 1))
    fi
    bearer_count=$(grep -Eoc 'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9_.-]{12,}' "$log_file" || true)
    raw_bearer_occurrences=$((raw_bearer_occurrences + bearer_count))
  fi
done <"$run_ids"

file_match_count=$(wc -l <"$file_matches")
output=/var/lib/paperclip/acceptance-evidence/secret-audit.json
mkdir -p "$(dirname "$output")"
jq -nc \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson credentialValuesCompared "$secret_count" \
  --argjson filesWithActualSecretMatches "$file_match_count" \
  --argjson runsScanned "$runs_scanned" \
  --argjson runLogsWithActualSecretMatches "$secret_log_matches" \
  --argjson rawBearerOccurrences "$raw_bearer_occurrences" \
  --slurpfile matchedFiles <(jq -Rsc 'split("\n")|map(select(length>0))' "$file_matches") \
  '{timestamp:$timestamp,credentialValuesCompared:$credentialValuesCompared,filesWithActualSecretMatches:$filesWithActualSecretMatches,matchedFiles:($matchedFiles[0] // []),runsScanned:$runsScanned,runLogsWithActualSecretMatches:$runLogsWithActualSecretMatches,rawBearerOccurrences:$rawBearerOccurrences,pass:($filesWithActualSecretMatches==0 and $runLogsWithActualSecretMatches==0 and $rawBearerOccurrences==0 and $runsScanned>0)}' \
  >"$output"
chmod 0640 "$output"
jq . "$output"
jq -e '.pass == true' "$output" >/dev/null
