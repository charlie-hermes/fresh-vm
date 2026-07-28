#!/bin/bash
set -Eeuo pipefail

check=files/ops/paperclip-http-denial-check
company=d7e2e389-c7ad-486e-8c86-cbbcd1fe06cd
probe=agency-core-brand-brief-steward-test-boot
valid="[12:34:56] \033[33mWARN\033[39m: \033[36mPOST /companies/$company/issues?acceptanceProbe=$probe 403\033[39m"

printf '%b\n' "$valid" | "$check" "$company" "$probe" >/dev/null
for invalid in \
  "POST /api/companies/$company/issues?acceptanceProbe=$probe 403" \
  "POST /companies/$company/issues?acceptanceProbe=$probe 400" \
  "POST /companies/$company/issues?acceptanceProbe=other 403"
do
  if printf '%s\n' "$invalid" | "$check" "$company" "$probe" 2>/dev/null; then
    echo "invalid denial trace unexpectedly passed: $invalid" >&2
    exit 1
  fi
done

if printf '%b\n%b\n' "$valid" "$valid" |
   "$check" "$company" "$probe" 2>/dev/null; then
  echo "duplicate denial traces unexpectedly passed" >&2
  exit 1
fi

echo "HTTP DENIAL EVIDENCE TEST PASS"
