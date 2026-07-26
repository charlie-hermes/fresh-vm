#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

test "$(id -u)" -eq 0 || { echo "root required" >&2; exit 77; }
board=/opt/paperclip/ops/paperclip-board-api
evidence_dir=/var/lib/paperclip/acceptance-evidence
evidence=$evidence_dir/functional-acceptance.json
boot_id=$(tr -d '\n' </proc/sys/kernel/random/boot_id)
company_id=$(tr -d '\n' </etc/paperclip/company-id)
agent_ids=/etc/paperclip/hermes-agent-ids.json
install -d -o root -g paperclip -m 0750 "$evidence_dir"

if test -f "$evidence" &&
   jq -e --arg boot "$boot_id" '.pass==true and .bootId==$boot and
     (.roles|length)==4 and all(.roles[];.pass==true)' "$evidence" >/dev/null; then
  echo "Four-profile functional acceptance already passed on this boot."
  exit 0
fi

project_name="Fresh VM Acceptance"
projects=$("$board" GET "/companies/$company_id/projects")
project_id=$(jq -r --arg name "$project_name" \
  '.[] | select(.name==$name) | .id' <<<"$projects" | head -n 1)
if test -z "$project_id"; then
  payload=$(jq -nc --arg name "$project_name" --arg agent "$(jq -r .qa "$agent_ids")" \
    '{name:$name,description:"Retained post-reboot production-readiness evidence.",
      status:"in_progress",leadAgentId:$agent}')
  project=$(printf '%s' "$payload" | "$board" POST "/companies/$company_id/projects" -)
  project_id=$(jq -er .id <<<"$project")
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
for slug in operations research production qa; do
  agent_id=$(jq -er --arg slug "$slug" '.[$slug]' "$agent_ids")
  marker="fresh-vm-${slug}-${boot_id}"
  printf '%s\n' "$marker" >"/srv/paperclip/workspaces/$slug/profile-sentinel.txt"
  chown paperclip:paperclip "/srv/paperclip/workspaces/$slug/profile-sentinel.txt"
  case "$slug" in
    operations)
      description="Use your delegation tool once with two parallel child tasks
that return the exact non-secret words delegation-alpha and delegation-beta.
Comment beginning fresh-vm-acceptance-pass:operations and include both child
words, then mark done. On failure, comment the failure and mark blocked."
      ;;
    research)
      description="Use web_search_hermes to find the official Python language
documentation URL. Comment beginning fresh-vm-acceptance-pass:research and
include that URL, then mark done. On failure, comment the failure and mark
blocked."
      ;;
    production|qa)
      description="Perform the authorized Docker acceptance for $slug.
Read /workspace/profile-sentinel.txt and verify it is exactly $marker. Verify
/run/docker.sock and /var/run/docker.sock are absent. Use the file tool to
write exactly $marker plus one newline to
/workspace/fresh-vm-acceptance.txt and read it back. Comment beginning
fresh-vm-acceptance-pass:$slug and state the checks passed, then mark done. On
failure, comment the failure and mark blocked."
      ;;
  esac
  issue_payload=$(jq -nc --arg project "$project_id" --arg agent "$agent_id" \
    --arg title "Acceptance $slug $boot_id" --arg description "$description" \
    '{projectId:$project,title:$title,description:$description,status:"todo",
      priority:"high",assigneeAgentId:$agent,allowDuplicate:true}')
  issue=$(printf '%s' "$issue_payload" | "$board" POST "/companies/$company_id/issues" -)
  jq -n --arg slug "$slug" --arg agentId "$agent_id" --arg marker "$marker" \
    --arg issueId "$(jq -er .id <<<"$issue")" \
    --arg identifier "$(jq -er .identifier <<<"$issue")" \
    '{slug:$slug,agentId:$agentId,marker:$marker,issueId:$issueId,
      identifier:$identifier}' >"$work/$slug.json"
done

max_running=0
for attempt in $(seq 1 600); do
  pending=0
  running=0
  for slug in operations research production qa; do
    issue_id=$(jq -r .issueId "$work/$slug.json")
    runs=$("$board" GET "/issues/$issue_id/runs")
    run=$(jq -c 'sort_by(.createdAt // .startedAt // "") | last // {}' <<<"$runs")
    printf '%s\n' "$run" >"$work/$slug-run.json"
    status=$(jq -r '.status // "awaiting_dispatch"' <<<"$run")
    case "$status" in
      queued|awaiting_dispatch) pending=$((pending + 1)) ;;
      running) pending=$((pending + 1)); running=$((running + 1)) ;;
    esac
  done
  test "$running" -le 2 ||
    { echo "VM-wide concurrency limit exceeded: $running" >&2; exit 1; }
  test "$running" -le "$max_running" || max_running=$running
  test "$pending" -gt 0 || break
  if test $((attempt % 15)) -eq 0; then
    echo "Acceptance: $pending pending, $running running"
  fi
  sleep 2
done

: >"$work/results.jsonl"
all_pass=true
for slug in operations research production qa; do
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
  comment_pass=$(jq -e --arg agent "$agent_id" --arg prefix "fresh-vm-acceptance-pass:$slug" \
    'any(.[]; .authorAgentId==$agent and (.body|startswith($prefix)))' \
    <<<"$comments" >/dev/null && echo true || echo false)
  run_log=$("$board" GET "/heartbeat-runs/$run_id/log" | jq -r '.content // ""')
  if test "$slug" = operations; then
    delegation_pass=$(jq -e --arg agent "$agent_id" \
      'any(.[]; .authorAgentId==$agent and
        (.body|contains("delegation-alpha")) and (.body|contains("delegation-beta")))' \
      <<<"$comments" >/dev/null && echo true || echo false)
    grep -Eqi 'delegate(_task)?|delegation' <<<"$run_log" ||
      delegation_pass=false
  else
    delegation_pass=true
  fi
  tool_pass=true
  if test "$slug" = research; then
    grep -q 'web_search_hermes' <<<"$run_log" || tool_pass=false
  fi
  marker_pass=false
  marker_file=/srv/paperclip/workspaces/$slug/fresh-vm-acceptance.txt
  case "$slug" in
    production|qa)
      test -f "$marker_file" && test "$(tr -d '\n' <"$marker_file")" = "$marker" &&
        marker_pass=true
      ;;
    *) marker_pass=true ;;
  esac

  container_pass=true
  if test "$slug" = production || test "$slug" = qa; then
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
  fi
  role_pass=false
  if test -n "$run_id" && test "$run_status" = succeeded &&
     test "$run_exit" = 0 && test "$issue_status" = done &&
     test "$comment_pass" = true && test "$delegation_pass" = true &&
     test "$tool_pass" = true && test "$marker_pass" = true &&
     test "$container_pass" = true; then
    role_pass=true
  else
    all_pass=false
  fi
  jq -nc --arg slug "$slug" --arg agentId "$agent_id" --arg issueId "$issue_id" \
    --arg runId "$run_id" --arg runStatus "$run_status" \
    --arg issueStatus "$issue_status" --argjson exitCode "$run_exit" \
    --argjson commentPass "$comment_pass" --argjson markerPass "$marker_pass" \
    --argjson containerPass "$container_pass" --argjson delegationPass "$delegation_pass" \
    --argjson toolPass "$tool_pass" \
    --argjson pass "$role_pass" \
    '{slug:$slug,agentId:$agentId,issueId:$issueId,runId:$runId,
      runStatus:$runStatus,exitCode:$exitCode,issueStatus:$issueStatus,
      commentPass:$commentPass,markerPass:$markerPass,
      containerPass:$containerPass,delegationPass:$delegationPass,
      toolPass:$toolPass,pass:$pass}' \
    >>"$work/results.jsonl"
done

temporary=$(mktemp "$evidence_dir/.functional.XXXXXX")
jq -s --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg bootId "$boot_id" --arg companyId "$company_id" \
  --arg projectId "$project_id" --argjson maxConcurrentObserved "$max_running" \
  --argjson pass "$all_pass" \
  '{timestamp:$timestamp,bootId:$bootId,companyId:$companyId,projectId:$projectId,
    maxConcurrentObserved:$maxConcurrentObserved,roles:.,pass:$pass}' \
  "$work/results.jsonl" >"$temporary"
install -o root -g paperclip -m 0640 "$temporary" "$evidence"
rm -f "$temporary"
jq . "$evidence"
test "$all_pass" = true || { echo "Functional acceptance failed" >&2; exit 1; }
echo "Four-profile functional acceptance PASS"
