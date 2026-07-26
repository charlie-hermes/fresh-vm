# Rollback

## Safety first

Before rollback, capture a database/state backup and confirm no heartbeat run is queued/running. Roll back one component at a time and run its focused regression tests.

## Hermes source patches

The repository preserves both the locked upstream hashes and final overlays.
Rollback means deploying a reviewed earlier repository commit or changing a
pin/overlay in a new reviewed commit; do not replace installed code from an
unverified adjacent file.

- File tools and checkpoint mapping must move together with their focused test
  overlays.
- Docker interrupt and profile-isolation behavior share
  `tools/environments/docker.py`; roll them back as one tested unit.
- Delegation requires `tools/delegate_tool.py`, `run_agent.py`, and
  `HERMES_FORCE_SYNC_DELEGATION=1` to remain aligned.
- Web alias rollback changes only `tools/web_tools.py`, but still requires the
  web regression suite.

After any Docker identity rollback, stop/remove only Hermes containers whose bind-mounted state is preserved, then inspect fresh mounts before use. Without the profile-isolation patch, multiple arbitrary external `HERMES_HOME` agents must set `docker_persist_across_processes: false` or must not coexist.

## Paperclip patches

- Change the adapter `execute.js` overlay and locked final hash together to
  alter `paperclipApiUrl` behavior.
- Change the effective-run-fingerprint overlay and locked final hash together
  to alter session-stability behavior.
- The packaging repair consists only of five `dist/onboarding-assets` files copied from the same package version; removing them restores the broken installed package state and is not recommended. A clean reinstall of the fixed package is preferred.

Restart Paperclip and repeat adapter/session/API checks after rollback.

## Service/config rollback

Versioned reference files are under `/opt/paperclip/integration/build` and the
Git checkout used for deployment. Replace only the intended unit or script from
a reviewed commit, run `systemd-analyze verify`, `daemon-reload`, and restart.
Docker daemon configuration changes require a Docker restart and must be
followed by fail-closed and state-survival checks.

Removing `paperclip` from the Docker group revokes required rootful backend access and intentionally prevents Paperclip startup/execution. Do this only when decommissioning or after a tested rootless migration.

## Full decommission

Disable/stop Paperclip health/backup timers and Paperclip, preserve encrypted backups, then remove only explicitly enumerated Paperclip/Hermes state, workspaces, units, network, and service account. Do not use recursive deletion against `/home`, `/var/lib`, `/srv`, `/opt`, or a workspace root. Provider credentials and operator tokens must be revoked separately.
