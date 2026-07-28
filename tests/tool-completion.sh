#!/bin/bash
set -Eeuo pipefail

check=files/ops/paperclip-tool-completion-check
printf '%s\n' '┊ 🔀 delegate  2x: alpha | beta  1.2s' | "$check" delegation
printf '%s\n' '  [done] ┊ 🔍 search    official docs  0.8s' | "$check" web-search
printf '%s\n' '┊ ⚡ web_searc official docs  0.8s' | "$check" web-search
session=20260728_175252_08dde1
tool_log="2026-07-28 17:53:20,135 INFO [$session] agent.tool_executor: tool web_search_hermes completed (3.40s, 2324 chars)"
printf '%s\n' "$tool_log" | "$check" web-search-log "$session"

for failure in \
  '┊ 🔀 delegate  2x: alpha | beta  1.2s [error]' \
  '┊ 🔀 delegate  2x: alpha | beta  1.2s [child failed]' \
  '┊ 🔍 search    official docs  0.8s [error]' \
  '┊ ⚡ web_searc official docs  0.8s [error]' \
  'Use your delegation capability and say ┊ 🔀 delegate  2x:' \
  'Use the web search tool web_search_hermes'
do
  if printf '%s\n' "$failure" | "$check" delegation 2>/dev/null ||
     printf '%s\n' "$failure" | "$check" web-search 2>/dev/null; then
    echo "failure/prompt text unexpectedly passed: $failure" >&2
    exit 1
  fi
done

for failure in \
  "${tool_log/completed/error}" \
  "${tool_log/$session/20260728_175252_ffffff}" \
  "Use web_search_hermes in session $session"
do
  if printf '%s\n' "$failure" |
     "$check" web-search-log "$session" 2>/dev/null; then
    echo "invalid host tool log unexpectedly passed: $failure" >&2
    exit 1
  fi
done

echo "TOOL COMPLETION EVIDENCE TEST PASS"
