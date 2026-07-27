#!/bin/bash
set -Eeuo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$repo/configure-snapshot-only.sh"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
auth=$work/auth.json
printf '%s\n' \
  '{"version":1,"providers":{},"active_provider":"openai-codex","credential_pool":{}}' \
  >"$auth"

printf '#!/bin/sh\nprintf "%%s\\n" "openai-codex: logged in"\n' >"$work/runuser-ok"
printf '#!/bin/sh\nprintf "%%s\\n" "openai-codex: logged out"\n' >"$work/runuser-out"
chmod 0755 "$work/runuser-ok" "$work/runuser-out"

make_profiles() {
  rm -rf -- "$work/agents"
  for slug in operations research production qa; do
    mkdir -p "$work/agents/$slug/home"
    : >"$work/agents/$slug/home/CREDENTIAL_REQUIRED"
  done
}

printf '%s\n' '#!/bin/bash' 'exit 70' >"$work/installer-fail"
chmod 0755 "$work/installer-fail"

printf '%s\n' \
  '#!/bin/bash' \
  'set -Eeuo pipefail' \
  'for slug in operations research production qa; do' \
  '  install -m 0600 "$1" "$SNAPSHOT_TEST_AGENTS/$slug/home/auth.json"' \
  '  rm -f -- "$SNAPSHOT_TEST_AGENTS/$slug/home/CREDENTIAL_REQUIRED"' \
  'done' >"$work/installer-ok"
chmod 0755 "$work/installer-ok"

printf '%s\n' \
  '#!/bin/bash' \
  'set -Eeuo pipefail' \
  'for slug in operations research production qa; do' \
  '  install -m 0600 "$1" "$SNAPSHOT_TEST_AGENTS/$slug/home/auth.json"' \
  '  rm -f -- "$SNAPSHOT_TEST_AGENTS/$slug/home/CREDENTIAL_REQUIRED"' \
  'done' \
  'exit 70' >"$work/installer-resume-fail"
chmod 0755 "$work/installer-resume-fail"

test_identity=600:$(id -un):$(id -gn)
mkdir "$work/state"
make_profiles
if SNAPSHOT_TEST_AGENTS=$work/agents snapshot_commission "$auth" \
    "$work/installer-fail" "$work/state" "$work/agents" /bin/true \
    "$work/runuser-ok" "$test_identity" "$test_identity" 2>/dev/null; then
  echo "resume/install failure was accepted" >&2
  exit 1
fi
test ! -e "$work/state/snapshot-only-commissioned"

make_profiles
if SNAPSHOT_TEST_AGENTS=$work/agents snapshot_commission "$auth" \
    "$work/installer-resume-fail" "$work/state" "$work/agents" /bin/true \
    "$work/runuser-ok" "$test_identity" "$test_identity" 2>/dev/null; then
  echo "resume failure was accepted" >&2
  exit 1
fi
test ! -e "$work/state/snapshot-only-commissioned"

printf '%s\n' '{}' >"$work/invalid.json"
if snapshot_validate_auth_source "$work/invalid.json"; then
  echo "invalid auth source was accepted" >&2
  exit 1
fi
ln -s "$auth" "$work/auth-link.json"
if snapshot_validate_auth_source "$work/auth-link.json"; then
  echo "symlink auth source was accepted" >&2
  exit 1
fi

make_profiles
rm -rf -- "$work/agents/qa"
if SNAPSHOT_TEST_AGENTS=$work/agents snapshot_commission "$auth" \
    "$work/installer-ok" "$work/state" "$work/agents" /bin/true \
    "$work/runuser-ok" "$test_identity" "$test_identity" 2>/dev/null; then
  echo "missing profile was accepted" >&2
  exit 1
fi
test ! -e "$work/state/snapshot-only-commissioned"

make_profiles
SNAPSHOT_TEST_AGENTS=$work/agents "$work/installer-ok" "$auth"
chmod 0644 "$work/agents/research/home/auth.json"
if snapshot_verify_profiles "$work/agents" /bin/true \
    "$work/runuser-ok" "$test_identity" 2>/dev/null; then
  echo "wrong credential mode was accepted" >&2
  exit 1
fi
chmod 0600 "$work/agents/research/home/auth.json"
: >"$work/agents/research/home/CREDENTIAL_REQUIRED"
if snapshot_verify_profiles "$work/agents" /bin/true \
    "$work/runuser-ok" "$test_identity" 2>/dev/null; then
  echo "lingering requirement marker was accepted" >&2
  exit 1
fi
rm -f -- "$work/agents/research/home/CREDENTIAL_REQUIRED"
if snapshot_verify_profiles "$work/agents" /bin/true \
    "$work/runuser-out" "$test_identity" 2>/dev/null; then
  echo "logged-out auth status was accepted" >&2
  exit 1
fi
if SNAPSHOT_TEST_AGENTS=$work/agents snapshot_commission "$auth" \
    "$work/installer-ok" "$work/state" "$work/agents" /bin/true \
    "$work/runuser-out" "$test_identity" "$test_identity" 2>/dev/null; then
  echo "commissioning accepted logged-out auth status" >&2
  exit 1
fi
test ! -e "$work/state/snapshot-only-commissioned"

make_profiles
SNAPSHOT_TEST_AGENTS=$work/agents snapshot_commission "$auth" \
  "$work/installer-ok" "$work/state" "$work/agents" /bin/true \
  "$work/runuser-ok" "$test_identity" "$test_identity"
SNAPSHOT_TEST_AGENTS=$work/agents snapshot_commission "$auth" \
  "$work/installer-ok" "$work/state" "$work/agents" /bin/true \
  "$work/runuser-ok" "$test_identity" "$test_identity"
test "$(stat -c '%a:%U:%G' "$work/state/snapshot-only-commissioned")" = \
  "$test_identity"
grep -qx 'mode=snapshot-only' "$work/state/snapshot-only-commissioned"
grep -qx 'accepted-risk=provider-snapshots' \
  "$work/state/snapshot-only-commissioned"
test ! -e "$work/state/configured-boot-id"
test ! -e "$work/state/offsite-status"

echo "SNAPSHOT-ONLY VALIDATION PASS"
