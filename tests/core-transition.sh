#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

run_case() {
  local direction=$1 checkpoint=$2 injection=${3:-term} expected case_root rc
  case_root=$work/$direction-$checkpoint-$injection
  mkdir -p "$case_root"
  case "$injection" in
    hup) expected=129 ;;
    int) expected=130 ;;
    term) expected=143 ;;
    error) expected=97 ;;
    *) echo "unknown injection: $injection" >&2; exit 64 ;;
  esac
  set +e
  REPO="$repo" CASE_ROOT="$case_root" DIRECTION="$direction" \
    FAIL_AT="$checkpoint" INJECTION="$injection" bash -ceu '
      source "$REPO/scripts/core-role-transition"
      state=$CASE_ROOT/state
      legacy_ids=$state/legacy-agent-ids.json
      core_ids=$state/core-agent-ids.json
      status_file=$state/status.json
      previous_status=$state/status.before-transition
      current_map=$CASE_ROOT/current-agent-ids.json
      mkdir -p "$state"
      printf '\''{"operations":"legacy-agent"}\n'\'' >"$legacy_ids"
      printf '\''{"agency-director":"core-agent"}\n'\'' >"$core_ids"
      printf '\''paused\n'\'' >"$CASE_ROOT/legacy.status"
      printf '\''paused\n'\'' >"$CASE_ROOT/core.status"

      set_agent_status() {
        local ids_file=$1 new_status=$2
        if test "$ids_file" = "$legacy_ids"; then
          printf '\''%s\n'\'' "$new_status" >"$CASE_ROOT/legacy.status"
        else
          printf '\''%s\n'\'' "$new_status" >"$CASE_ROOT/core.status"
        fi
      }
      install_identity_map() { cp "$1" "$current_map"; }
      copy_status_file() { cp "$1" "$2"; }
      reset_core_sessions() { :; }
      write_activation_status() { printf '\''{"status":"active"}\n'\'' >"$status_file"; }
      write_rollback_status() { printf '\''{"status":"rolled_back"}\n'\'' >"$status_file"; }
      clear_functional_evidence() { :; }
      transition_checkpoint() {
        test "$1" != "$FAIL_AT" || {
          case "$INJECTION" in
            hup) kill -HUP "$$" ;;
            int) kill -INT "$$" ;;
            term) kill -TERM "$$" ;;
            error) return 97 ;;
          esac
        }
      }

      case "$DIRECTION" in
        activate)
          cp "$legacy_ids" "$current_map"
          printf '\''idle\n'\'' >"$CASE_ROOT/legacy.status"
          perform_activation_cutover
          ;;
        rollback)
          cp "$core_ids" "$current_map"
          printf '\''idle\n'\'' >"$CASE_ROOT/core.status"
          printf '\''{"status":"active","sourceCommit":"candidate"}\n'\'' >"$status_file"
          perform_rollback_cutover
          ;;
      esac
      exit 99
    ' >/dev/null 2>&1
  rc=$?
  set -e
  test "$rc" -eq "$expected" || {
    echo "$direction/$checkpoint/$injection exited $rc, expected $expected" >&2
    exit 1
  }
  if test "$direction" = activate; then
    cmp "$case_root/state/legacy-agent-ids.json" "$case_root/current-agent-ids.json"
    grep -qx idle "$case_root/legacy.status"
    grep -qx paused "$case_root/core.status"
    test ! -f "$case_root/state/status.json"
  else
    cmp "$case_root/state/core-agent-ids.json" "$case_root/current-agent-ids.json"
    grep -qx idle "$case_root/core.status"
    grep -qx paused "$case_root/legacy.status"
    jq -e '.status=="active" and .sourceCommit=="candidate"' \
      "$case_root/state/status.json" >/dev/null
  fi
  test ! -f "$case_root/state/status.before-transition"
}

for checkpoint in legacy-paused core-map-installed core-resumed sessions-reset status-written; do
  for injection in hup int term error; do
    run_case activate "$checkpoint" "$injection"
  done
done
for checkpoint in core-paused legacy-map-installed legacy-resumed rollback-status-written; do
  for injection in hup int term error; do
    run_case rollback "$checkpoint" "$injection"
  done
done

echo "CORE TRANSITION SIGNAL/ERROR RESTORATION PASS"
