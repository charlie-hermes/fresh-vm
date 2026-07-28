# Operations runbook

## Normal checks

```sh
sudo systemctl status paperclip docker containerd --no-pager
sudo systemctl status paperclip-health.timer paperclip-soak-sample.timer --no-pager
curl -fsS http://172.30.0.1:3100/api/health | jq .
sudo ss -lntp | grep -E '(:3100|:54329)'
sudo docker ps --filter label=hermes-agent=1
sudo journalctl -u paperclip.service -n 200 --no-pager
```

Expected listeners are `172.30.0.1:3100` and `127.0.0.1:54329`. Public `0.0.0.0:3100` or `[::]:3100` is a fault.

## Start, stop, restart

```sh
sudo systemctl restart paperclip.service
sudo systemctl stop paperclip.service
sudo systemctl start paperclip.service
```

Docker/containerd are vendor units and must remain enabled. Paperclip requires Docker and fails its `ExecStartPre` socket check when Docker is unavailable; it does not fall back to host terminal execution.

## Interrupted bootstrap

Rerun `sudo ./bootstrap.sh`. Profile creation and finalization use completion
markers and repair partial files. A completed appliance also removes stale
pending/bootstrap material before verifying. If a legacy interrupted build has
`precomplete` but lost `bootstrap/admin.env`, the installer stops instead of
inventing credentials for a possibly existing administrator; preserve the VM
and recover or rebuild from a clean VM.

Before a planned VM reboot, confirm the company heartbeat-run list has no `queued` or `running` entries. Paperclip 2026.720.0 can log a graceful-run-drain query warning during shutdown when embedded PostgreSQL closes first; if the pre-shutdown run count was zero, systemd deactivated cleanly, post-boot health is green, and a smoke heartbeat succeeds, this is the documented upstream ordering limitation rather than state loss.

## Health and disk

```sh
sudo systemctl start paperclip-health.service
sudo journalctl -u paperclip-health.service -n 100 --no-pager
sudo docker system df
df -h /
```

The health timer runs every minute and fails above 85% filesystem use or on unhealthy service/API/Docker/network state.

The soak timer records a redacted JSON health sample every fifteen minutes at `/var/lib/paperclip/soak/samples.jsonl`. Review it with:

```sh
sudo systemctl status paperclip-soak-sample.timer --no-pager
sudo tail -n 20 /var/lib/paperclip/soak/samples.jsonl | jq .
```

VM snapshots, backups, and recovery are handled by the human VM owner outside
this project. The bundled backup tools remain available for optional manual use,
but their services and timers are disabled by default and are not release
requirements.

## Changing or upgrading the eight-role factory

The released appliance verifies exactly eight active Core profiles. Adding,
removing, renaming, or re-authorising a role is a factory change, not an ad-hoc
production operation: update the registry, initializer, profile builder,
credential installer, functional acceptance, exact-count
verification, and installed-asset locks together in a reviewed release.

For an appliance running the prior four-profile release, use only the reviewed
transition command from the release checkout:

```sh
sudo ./scripts/core-role-transition activate
sudo ./verify.sh
```

The transition refuses live runs/containers, preserves the legacy identity map,
installs checksum-locked assets, and pauses the eight new profiles while they
are prepared. It verifies legacy credential copies without printing them, then
atomically changes the active identity map. Legacy employees and profile data
are retained for rollback; they are not deleted.

A runtime-only rollback is available after confirming the employee plane is
quiescent:

```sh
sudo /usr/local/sbin/paperclip-core-role-transition rollback
```

Rollback pauses the Core roles and restores the legacy identity map. Then deploy
the prior reviewed repository commit so installed verification assets match the
restored runtime. Do not claim production readiness while code and runtime are
on different releases.

For every future factory change:

1. Allocate a unique `/var/lib/paperclip/agents/<role>/home` and `/srv/paperclip/workspaces/<role>` owned by `paperclip:paperclip`.
2. Install the checksum-bound `SOUL.md` in the home and `AGENTS.md` in the workspace; upload the same AGENTS bytes to Paperclip's managed bundle.
3. Initialize a separate Hermes configuration/credential copy; never share sessions, memory, state DB, sandbox home, or writable credential files.
4. Confirm the workspace remains below `/srv/paperclip/workspaces` and keeps credentials and logs isolated from task artifacts.
5. Set adapter `env.HERMES_HOME` and `cwd` to the exact unique paths.
6. Reset the runtime session, prove both context files loaded through the pinned Hermes prompt builder, then run a real Paperclip assignment.
7. Verify every denied toolset, workspace sentinel, container mount, socket absence, role comment, and global concurrency evidence.
8. Never reuse a `HERMES_HOME` across agents.

## MCP

The local acceptance echo server proved stdio MCP, then was unregistered. Production intentionally has no MCP server configured. Add only reviewed servers with:

```sh
sudo -u paperclip env HOME=/var/lib/paperclip HERMES_HOME=/var/lib/paperclip/agents/agency-director/home /opt/hermes-agent/7de554277de632364c74fcf8641daa58a9a977d9/venv/bin/hermes mcp add ...
```

Re-test boundaries and credentials after changes.

## Incident guidance

- Paperclip unhealthy: inspect `journalctl`, health JSON, embedded PG listener, disk, and Docker.
- Docker down: restore Docker first; Paperclip is ordered/requires it. Do not change terminal backend to local.
- Stuck run: inspect the heartbeat run, process group, and labeled container. Use Paperclip's run controls before manual signals.
- Suspected cross-profile reuse: compare `hermes-profile` label and every bind source with the agent's `HERMES_HOME`; stop work if mismatched.
- Disk pressure: preserve backups/state, then prune only resolved stale acceptance containers/images. Do not delete active profile homes or workspaces.
- Credentials: rotate `/etc/paperclip/operator.env` through Paperclip mechanisms and profile auth through Hermes login; never edit reports to include values.

## Emergency stop and recovery

```sh
sudo /opt/paperclip/ops/paperclip-emergency-control status
sudo /opt/paperclip/ops/paperclip-emergency-control stop
sudo /opt/paperclip/ops/paperclip-emergency-control resume
```

`stop` snapshots only agents that were not already paused, pauses them, cancels live/queued runs, and stops every `hermes-agent=1` container. `resume` restores only the snapshotted agents to idle; it must not unpause regression or built-in helper agents.

After resume, inspect every issue that was `in_progress` or queued at the stop boundary. Paperclip may create a `stranded_assigned_issue` recovery action and set the source issue to `blocked`. Use `GET /api/issues/{id}/recovery-actions` through the root board client. Resolve with `outcome: restored, sourceIssueStatus: done` only when a durable artifact/comment proves completion; otherwise restore to `todo` to hand work back. Never mark an interrupted issue done merely because its adapter run succeeded.

A `handed_back` recovery can produce a short validation heartbeat whose only job is to confirm the runtime path and leave the issue in `todo`; it is not proof that the original deliverable was completed. After that validation run ends, verify that no live run owns the issue, then add a normal board dispatch comment (or use the ordinary scheduler path) to wake the assignee for the original work. Distinguish the recovery-validation run from the subsequent business-work run in the incident record.

If blocker diagnostics report `allBlockersDone: true` while an issue remains `blocked`, the board may clear the stale hold by moving it to `todo`. Record why. Avoid combining a human board comment with a new unresolved `blockedByIssueIds` relation: this release can queue an unnecessary assignee wake from the comment even though dependency checkout remains blocked.

## Employee adapter configuration (redacted)

```json
{
  "adapterType": "hermes_local",
  "adapterConfig": {
    "hermesCommand": "/opt/hermes-agent/7de554277de632364c74fcf8641daa58a9a977d9/venv/bin/hermes",
    "cwd": "/srv/paperclip/workspaces/<slug>",
    "provider": "openai-codex",
    "model": "gpt-5.6-sol",
    "quiet": true,
    "verbose": false,
    "persistSession": true,
    "checkpoints": true,
    "worktreeMode": false,
    "timeoutSec": 900,
    "graceSec": 20,
    "maxTurnsPerRun": 40,
    "paperclipApiUrl": "http://paperclip-host:3100",
    "extraArgs": ["--pass-session-id"]
  }
}
```

No API keys are stored in this object. Omitted toolsets means all installed/available toolsets; both `toolsets` and `enabledToolsets` are not supplied.
