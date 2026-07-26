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
qa_id=$(jq -er '.qa' /etc/paperclip/hermes-agent-ids.json)
marker="fresh-vm-functional-${boot_id}"
install -d -o root -g paperclip -m 0750 "$evidence_dir"

if [ -f "$evidence" ] &&
   jq -e --arg boot "$boot_id" '.pass==true and .bootId==$boot' "$evidence" >/dev/null; then
  echo "Functional acceptance already passed on this boot."
  exit 0
fi

project_name="Fresh VM Acceptance"
projects=$("$board" GET "/companies/$company_id/projects")
project_id=$(jq -r --arg name "$project_name" \
  '.[] | select(.name==$name) | .id' <<<"$projects" | head -n 1)
if [ -z "$project_id" ]; then
  project_payload=$(jq -nc --arg name "$project_name" --arg agent "$qa_id" \
    '{name:$name,description:"Retained post-reboot production-readiness evidence.",status:"in_progress",leadAgentId:$agent}')
  project=$(printf '%s' "$project_payload" |
    "$board" POST "/companies/$company_id/projects" -)
  project_id=$(jq -er '.id' <<<"$project")
fi

description=$(cat <<EOF
Perform the authorized post-reboot functional acceptance in your Docker sandbox.

1. With terminal, verify pwd is /workspace.
2. Verify /run/docker.sock and /var/run/docker.sock are both absent.
3. Write exactly "$marker" followed by one newline to /workspace/fresh-vm-acceptance.txt and read it back.
4. Run "paperclip-api GET /agents/me" and verify the returned id equals PAPERCLIP_AGENT_ID. Never print or expose any credential.
5. Add an issue comment beginning "fresh-vm-acceptance-pass" that states the workspace, socket, marker, and identity checks passed.
6. Mark this issue done.

If any check fails, comment the exact failed check, mark the issue blocked, and do not claim a pass.
EOF
)
issue_payload=$(jq -nc \
  --arg project "$project_id" --arg agent "$qa_id" \
  --arg title "Post-reboot functional acceptance $boot_id" \
  --arg description "$description" \
  '{projectId:$project,title:$title,description:$description,status:"todo",priority:"high",assigneeAgentId:$agent,allowDuplicate:true}')
issue=$(printf '%s' "$issue_payload" |
  "$board" POST "/companies/$company_id/issues" -)
issue_id=$(jq -er '.id' <<<"$issue")
identifier=$(jq -er '.identifier' <<<"$issue")
echo "Functional acceptance issue created: $identifier"

run='{}'
run_id=
for attempt in $(seq 1 600); do
  runs=$("$board" GET "/issues/$issue_id/runs")
  run=$(jq -c 'sort_by(.createdAt // .startedAt // "") | last // {}' <<<"$runs")
  run_id=$(jq -r '.id // empty' <<<"$run")
  status=$(jq -r '.status // "awaiting_dispatch"' <<<"$run")
  case "$status" in
    queued|running|awaiting_dispatch) ;;
    *) break ;;
  esac
  if [ $((attempt % 15)) -eq 0 ]; then
    echo "Functional acceptance status: $status"
  fi
  sleep 2
done

issue=$("$board" GET "/issues/$issue_id")
comments=$("$board" GET "/issues/$issue_id/comments")
run_status=$(jq -r '.status // "missing"' <<<"$run")
run_exit=$(jq -r '.exitCode // -1' <<<"$run")
issue_status=$(jq -r '.status // "missing"' <<<"$issue")
comment_pass=$(jq -e --arg qa "$qa_id" \
  'any(.[]; .authorAgentId==$qa and (.body | startswith("fresh-vm-acceptance-pass")))' \
  <<<"$comments" >/dev/null && echo true || echo false)
marker_pass=false
if [ -f /srv/paperclip/workspaces/qa/fresh-vm-acceptance.txt ] &&
   [ "$(tr -d '\n' </srv/paperclip/workspaces/qa/fresh-vm-acceptance.txt)" = "$marker" ]; then
  marker_pass=true
fi
pass=false
if [ -n "$run_id" ] && [ "$run_status" = succeeded ] &&
   [ "$run_exit" = 0 ] && [ "$issue_status" = "done" ] &&
   [ "$comment_pass" = true ] && [ "$marker_pass" = true ]; then
  pass=true
fi

temporary=$(mktemp "$evidence_dir/.functional.XXXXXX")
jq -n \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg bootId "$boot_id" --arg companyId "$company_id" \
  --arg projectId "$project_id" --arg issueId "$issue_id" \
  --arg identifier "$identifier" --arg qaAgentId "$qa_id" \
  --arg runId "$run_id" --arg runStatus "$run_status" \
  --arg issueStatus "$issue_status" --argjson exitCode "$run_exit" \
  --argjson commentPass "$comment_pass" --argjson markerPass "$marker_pass" \
  --argjson pass "$pass" \
  '{timestamp:$timestamp,bootId:$bootId,companyId:$companyId,projectId:$projectId,
    issueId:$issueId,identifier:$identifier,qaAgentId:$qaAgentId,runId:$runId,
    runStatus:$runStatus,exitCode:$exitCode,issueStatus:$issueStatus,
    commentPass:$commentPass,markerPass:$markerPass,pass:$pass}' >"$temporary"
install -o root -g paperclip -m 0640 "$temporary" "$evidence"
rm -f "$temporary"
jq . "$evidence"
test "$pass" = true || { echo "Functional acceptance failed" >&2; exit 1; }
echo "Functional acceptance PASS"
