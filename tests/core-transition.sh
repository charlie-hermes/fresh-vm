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
    exit) expected=98 ;;
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
      reconcile_snapshot=$state/reconcile-agent-snapshot.json
      reconcile_core_ids=$state/core-agent-ids.before-reconcile.json
      reconcile_files=$state/core-managed-files.before-reconcile.tar
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
      restore_reconcile_files() {
        printf '\''restored\n'\'' >"$CASE_ROOT/reconcile-files.restored"
      }
      restore_reconcile_agents() {
        printf '\''restored\n'\'' >"$CASE_ROOT/reconcile.restored"
        printf '\''idle\n'\'' >"$CASE_ROOT/core.status"
      }
      transition_checkpoint() {
        test "$1" != "$FAIL_AT" || {
          case "$INJECTION" in
            hup) kill -HUP "$$" ;;
            int) kill -INT "$$" ;;
            term) kill -TERM "$$" ;;
            exit) exit 98 ;;
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
        reconcile)
          cp "$core_ids" "$current_map"
          cp "$core_ids" "$reconcile_core_ids"
          printf '\''idle\n'\'' >"$CASE_ROOT/core.status"
          printf '\''paused\n'\'' >"$CASE_ROOT/legacy.status"
          printf '\''{"status":"active","sourceCommit":"candidate"}\n'\'' >"$status_file"
          printf '\''snapshot\n'\'' >"$reconcile_snapshot"
          printf '\''managed files\n'\'' >"$reconcile_files"
          arm_transition reconcile
          printf '\''{"agency-director":"replacement-agent"}\n'\'' >"$core_ids"
          perform_activation_cutover reconcile
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
  elif test "$direction" = reconcile; then
    cmp "$case_root/state/core-agent-ids.json" "$case_root/current-agent-ids.json"
    grep -qx idle "$case_root/core.status"
    grep -qx paused "$case_root/legacy.status"
    grep -qx restored "$case_root/reconcile.restored"
    grep -qx restored "$case_root/reconcile-files.restored"
    jq -e '.status=="active" and .sourceCommit=="candidate"' \
      "$case_root/state/status.json" >/dev/null
    test ! -f "$case_root/state/reconcile-agent-snapshot.json"
    test ! -f "$case_root/state/core-agent-ids.before-reconcile.json"
    test ! -f "$case_root/state/core-managed-files.before-reconcile.tar"
  else
    cmp "$case_root/state/core-agent-ids.json" "$case_root/current-agent-ids.json"
    grep -qx idle "$case_root/core.status"
    grep -qx paused "$case_root/legacy.status"
    jq -e '.status=="active" and .sourceCommit=="candidate"' \
      "$case_root/state/status.json" >/dev/null
  fi
  test ! -f "$case_root/state/status.before-transition"
}

for checkpoint in core-agents-prepared legacy-paused core-map-installed core-resumed sessions-reset status-written; do
  for injection in hup int term exit error; do
    run_case activate "$checkpoint" "$injection"
    run_case reconcile "$checkpoint" "$injection"
  done
done
for checkpoint in core-paused legacy-map-installed legacy-resumed rollback-status-written; do
  for injection in hup int term exit error; do
    run_case rollback "$checkpoint" "$injection"
  done
done

run_restore_failure() {
  local failure=$1 case_root=$work/restore-$1 rc artifact
  case_root=$work/restore-$failure
  mkdir -p "$case_root"
  set +e
  REPO="$repo" CASE_ROOT="$case_root" FAILURE="$failure" \
    bash -ceu '
      source "$REPO/scripts/core-role-transition"
      state=$CASE_ROOT/state
      legacy_ids=$state/legacy-agent-ids.json
      core_ids=$state/core-agent-ids.json
      status_file=$state/status.json
      previous_status=$state/status.before-transition
      reconcile_snapshot=$state/reconcile-agent-snapshot.json
      reconcile_core_ids=$state/core-agent-ids.before-reconcile.json
      reconcile_files=$state/core-managed-files.before-reconcile.tar
      mkdir -p "$state"
      printf '\''{"operations":"legacy-agent"}\n'\'' >"$legacy_ids"
      printf '\''{"agency-director":"replacement-agent"}\n'\'' >"$core_ids"
      printf '\''{"secondary":"prior-fail","agency-director":"prior-success"}\n'\'' >"$reconcile_core_ids"
      printf '\''{"status":"active","sourceCommit":"prior"}\n'\'' >"$previous_status"
      printf '\''{"status":"active","sourceCommit":"candidate"}\n'\'' >"$status_file"
      printf '\''snapshot\n'\'' >"$reconcile_snapshot"
      printf '\''managed files\n'\'' >"$reconcile_files"

      if test "$FAILURE" != partial-pause; then
        set_agent_status() {
          local ids_file=$1
          test "$FAILURE" != current-pause || test "$ids_file" != "$core_ids" || return 91
          test "$FAILURE" != saved-pause || test "$ids_file" != "$reconcile_core_ids" || return 92
        }
      fi
      api_call() {
        local path=$2
        printf '\''%s\n'\'' "$path" >>"$CASE_ROOT/api-calls"
        test "$FAILURE" != partial-pause || test "$path" != /agents/prior-fail
      }
      install_identity_map() {
        test "$FAILURE" != identity-map || return 93
        cp "$1" "$CASE_ROOT/current-agent-ids.json"
      }
      restore_reconcile_files() { test "$FAILURE" != managed-files; }
      restore_reconcile_agents() { test "$FAILURE" != agents; }
      copy_status_file() {
        local source=$1
        if test "$source" = "$previous_status"; then
          : >"$CASE_ROOT/status-restore.attempted"
          test "$FAILURE" != transition-status || return 95
        fi
        test "$FAILURE" != core-ids || test "$source" != "$reconcile_core_ids" || return 94
        cp "$1" "$2"
      }
      transition_mode=reconcile
      restore_transition 97
    ' >"$case_root/output" 2>&1
  rc=$?
  set -e
  test "$rc" -eq 97 || {
    echo "restore/$failure exited $rc, expected 97" >&2
    exit 1
  }
  for artifact in reconcile-agent-snapshot.json core-agent-ids.before-reconcile.json \
    core-managed-files.before-reconcile.tar status.before-transition; do
    test -f "$case_root/state/$artifact"
  done
  if test "$failure" = partial-pause; then
    grep -qx /agents/prior-fail "$case_root/api-calls"
    grep -qx /agents/prior-success "$case_root/api-calls"
  fi
  test -f "$case_root/status-restore.attempted"
  grep -q 'recovery incomplete; recovery artifacts retained' "$case_root/output"
  ! grep -q 'prior Core runtime restored$' "$case_root/output"
}

for failure in current-pause saved-pause partial-pause identity-map managed-files agents core-ids \
  transition-status; do
  run_restore_failure "$failure"
done

echo "CORE TRANSITION SIGNAL/ERROR RESTORATION PASS"
