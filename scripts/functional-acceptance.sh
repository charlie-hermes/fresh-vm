#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

test "$(id -u)" -eq 0 || { echo "root required" >&2; exit 77; }
board=/opt/paperclip/ops/paperclip-board-api
bundle_verifier=/opt/paperclip/ops/runtime-bundle-verify
registry=/opt/paperclip/integration/factory/core-roles.tsv
evidence_dir=/var/lib/paperclip/acceptance-evidence
evidence=$evidence_dir/functional-acceptance.json
boot_id=$(tr -d '\n' </proc/sys/kernel/random/boot_id)
company_id=$(tr -d '\n' </etc/paperclip/company-id)
agent_ids=/etc/paperclip/hermes-agent-ids.json
install -d -o root -g paperclip -m 0750 "$evidence_dir"

if test -f "$evidence" &&
   jq -e --arg boot "$boot_id" '.pass==true and .bootId==$boot and
     (.roles|length)==8 and all(.roles[];.pass==true) and
     (.runtimeBundles|length)==8 and all(.runtimeBundles[];.pass==true)' \
     "$evidence" >/dev/null; then
  echo "Eight-role functional acceptance already passed on this boot."
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
"$bundle_verifier" >"$work/runtime-bundles.json"
jq -e 'length==8 and all(.[];
  .pass==true and .freshProcess==true and .soulLoadedExactly==true and
  .agentsLoadedExactly==true and .managedInstructionsExact==true)' \
  "$work/runtime-bundles.json" >/dev/null

project_name="Agency Core Runtime Acceptance"
projects=$("$board" GET "/companies/$company_id/projects")
project_id=$(jq -r --arg name "$project_name" \
  '.[] | select(.name==$name) | .id' <<<"$projects" | head -n 1)
if test -z "$project_id"; then
  payload=$(jq -nc --arg name "$project_name" \
    --arg agent "$(jq -r '.["editorial-integrity-qa"]' "$agent_ids")" \
    '{name:$name,description:"Retained eight-role runtime activation evidence.",
      status:"in_progress",leadAgentId:$agent}')
  project=$(printf '%s' "$payload" | "$board" POST "/companies/$company_id/projects" -)
  project_id=$(jq -er .id <<<"$project")
fi

while IFS=$'\t' read -r slug _; do
  case "$slug" in ''|\#*) continue;; esac
  agent_id=$(jq -er --arg slug "$slug" '.[$slug]' "$agent_ids")
  printf '{}' | "$board" POST "/agents/$agent_id/runtime-state/reset-session" - >/dev/null
  marker="agency-core-${slug}-${boot_id}"
  printf '%s\n' "$marker" >"/srv/paperclip/workspaces/$slug/profile-sentinel.txt"
  chown paperclip:paperclip "/srv/paperclip/workspaces/$slug/profile-sentinel.txt"
  description="Operate only as the configured $slug role. Read
/workspace/profile-sentinel.txt and verify it is exactly $marker. Verify
/run/docker.sock and /var/run/docker.sock are absent. Use the file tool to
write exactly $marker plus one newline to /workspace/runtime-acceptance.txt
and read it back. Comment beginning fresh-vm-role-pass:$slug and include
configured-role:$slug, then mark done. On failure, comment the failure and
mark blocked."
  case "$slug" in
    search-content-strategist|growth-intelligence-analyst)
      description="$description
Also use the approved web-search capability to find the official Python
language documentation URL and include that URL in the pass comment."
      ;;
  esac
  issue_payload=$(jq -nc --arg project "$project_id" --arg agent "$agent_id" \
    --arg title "Runtime acceptance $slug $boot_id" --arg description "$description" \
    '{projectId:$project,title:$title,description:$description,status:"todo",
      priority:"high",assigneeAgentId:$agent,allowDuplicate:true}')
  issue=$(printf '%s' "$issue_payload" | "$board" POST "/companies/$company_id/issues" -)
  jq -n --arg slug "$slug" --arg agentId "$agent_id" --arg marker "$marker" \
    --arg issueId "$(jq -er .id <<<"$issue")" \
    --arg identifier "$(jq -er .identifier <<<"$issue")" \
    '{slug:$slug,agentId:$agentId,marker:$marker,issueId:$issueId,
      identifier:$identifier,freshSessionRequested:true}' >"$work/$slug.json"
done <"$registry"

max_running=0
queued_observed=false
for attempt in $(seq 1 900); do
  pending=0
  running=0
  queued=0
  while IFS=$'\t' read -r slug _; do
    case "$slug" in ''|\#*) continue;; esac
    issue_id=$(jq -r .issueId "$work/$slug.json")
    runs=$("$board" GET "/issues/$issue_id/runs")
    run=$(jq -c 'sort_by(.createdAt // .startedAt // "") | last // {}' <<<"$runs")
    printf '%s\n' "$run" >"$work/$slug-run.json"
    status=$(jq -r '.status // "awaiting_dispatch"' <<<"$run")
    case "$status" in
      queued|awaiting_dispatch) pending=$((pending + 1)); queued=$((queued + 1)) ;;
      running) pending=$((pending + 1)); running=$((running + 1)) ;;
    esac
  done <"$registry"
  test "$running" -le 2 ||
    { echo "VM-wide concurrency limit exceeded: $running" >&2; exit 1; }
  test "$queued" -eq 0 || queued_observed=true
  test "$running" -le "$max_running" || max_running=$running
  test "$pending" -gt 0 || break
  if test $((attempt % 15)) -eq 0; then
    echo "Acceptance: $pending pending, $running running"
  fi
  sleep 2
done

: >"$work/results.jsonl"
all_pass=true
while IFS=$'\t' read -r slug _; do
  case "$slug" in ''|\#*) continue;; esac
  record=$work/$slug.json
  agent_id=$(jq -r .agentId "$record")
  marker=$(jq -r .marker "$record")
  issue_id=$(jq -r .issueId "$record")
  issue=$("$board" GET "/issues/$issue_id")
  comments=$("$board" GET "/issues/$issue_id/comments")
  run=$(cat "$work/$slug-run.json")
  run_id=$(jq -r '.id // empty' <<<"$run")
  run_status=$(jq -r '.status // "missing"' <<<"$run")
  run_exit=$(jq -r '.exitCode // -1' <<<"$run")
  issue_status=$(jq -r '.status // "missing"' <<<"$issue")
  comment_pass=$(jq -e --arg agent "$agent_id" \
    --arg prefix "fresh-vm-role-pass:$slug" --arg role "configured-role:$slug" \
    'any(.[]; .authorAgentId==$agent and (.body|startswith($prefix)) and
      (.body|contains($role)))' <<<"$comments" >/dev/null && echo true || echo false)
  run_log=$("$board" GET "/heartbeat-runs/$run_id/log?limitBytes=10485760" |
    jq -r '.content // ""')
  web_pass=true
  case "$slug" in
    search-content-strategist|growth-intelligence-analyst)
      printf '%s\n' "$run_log" |
        /opt/paperclip/ops/paperclip-tool-completion-check web-search || web_pass=false
      ;;
  esac
  marker_file=/srv/paperclip/workspaces/$slug/runtime-acceptance.txt
  marker_pass=false
  test -f "$marker_file" && test "$(tr -d '\n' <"$marker_file")" = "$marker" &&
    marker_pass=true
  container_pass=false
  while IFS= read -r candidate; do
    if docker inspect "$candidate" |
      jq -e --arg source "/srv/paperclip/workspaces/$slug" '
        (.[0].HostConfig.SecurityOpt|any(startswith("no-new-privileges"))) and
        (.[0].Mounts|any(.Source==$source and .Destination=="/workspace")) and
        (.[0].Mounts|all(.Source!="/var/run/docker.sock" and .Source!="/run/docker.sock"))
      ' >/dev/null; then
      container_pass=true
      break
    fi
  done < <(docker ps -aq --filter label=hermes-agent=1)
  role_pass=false
  if test -n "$run_id" && test "$run_status" = succeeded &&
     test "$run_exit" = 0 && test "$issue_status" = done &&
     test "$comment_pass" = true && test "$web_pass" = true &&
     test "$marker_pass" = true && test "$container_pass" = true; then
    role_pass=true
  else
    all_pass=false
  fi
  jq -nc --arg slug "$slug" --arg agentId "$agent_id" --arg issueId "$issue_id" \
    --arg runId "$run_id" --arg runStatus "$run_status" \
    --arg issueStatus "$issue_status" --argjson exitCode "$run_exit" \
    --argjson commentPass "$comment_pass" --argjson markerPass "$marker_pass" \
    --argjson containerPass "$container_pass" --argjson webPass "$web_pass" \
    --argjson pass "$role_pass" \
    '{slug:$slug,agentId:$agentId,issueId:$issueId,runId:$runId,
      runStatus:$runStatus,exitCode:$exitCode,issueStatus:$issueStatus,
      freshSessionRequested:true,commentPass:$commentPass,markerPass:$markerPass,
      containerPass:$containerPass,webPass:$webPass,pass:$pass}' \
    >>"$work/results.jsonl"
done <"$registry"

temporary=$(mktemp "$evidence_dir/.functional.XXXXXX")
jq -s --slurpfile bundles "$work/runtime-bundles.json" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg bootId "$boot_id" --arg companyId "$company_id" \
  --arg projectId "$project_id" --argjson maxConcurrentObserved "$max_running" \
  --argjson queuedObserved "$queued_observed" --argjson pass "$all_pass" \
  '{timestamp:$timestamp,bootId:$bootId,companyId:$companyId,projectId:$projectId,
    maxConcurrentObserved:$maxConcurrentObserved,queuedObserved:$queuedObserved,
    runtimeBundles:$bundles[0],roles:.,
    pass:($pass and $queuedObserved and $maxConcurrentObserved==2 and
      ($bundles[0]|length)==8 and all($bundles[0][];.pass==true))}' \
  "$work/results.jsonl" >"$temporary"
install -o root -g paperclip -m 0640 "$temporary" "$evidence"
rm -f "$temporary"
jq . "$evidence"
test "$all_pass" = true && test "$queued_observed" = true &&
  test "$max_running" -eq 2 ||
  { echo "Functional acceptance or global concurrency evidence failed" >&2; exit 1; }
echo "Eight-role functional acceptance PASS"
