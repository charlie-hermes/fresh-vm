#!/bin/bash
set -Eeuo pipefail

check=files/ops/paperclip-tool-completion-check
printf '%s\n' '┊ 🔀 delegate  2x: alpha | beta  1.2s' | "$check" delegation
printf '%s\n' '  [done] ┊ 🔍 search    official docs  0.8s' | "$check" web-search
printf '%s\n' '┊ ⚡ web_searc official docs  0.8s' | "$check" web-search

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

echo "TOOL COMPLETION EVIDENCE TEST PASS"
