# Versions, pins, and local remediations

## Host and components

- Ubuntu 24.04 LTS (`noble`), amd64; minimum 4 vCPU, a 12 GB-class allocation
  reporting at least 11,500,000 KiB RAM, 30 GiB free root-disk space, and
  1 GiB active swap.
- Paperclip 2026.720.0: `/opt/paperclip/2026.720.0`.
- Hermes Agent v0.19.0 (2026.7.20), commit `7de554277de632364c74fcf8641daa58a9a977d9`: `/opt/hermes-agent/7de554277de632364c74fcf8641daa58a9a977d9`.
- Docker 29.1.3; containerd 2.2.1; runc 1.3.4; cgroup v2; overlayfs.
- Node 22.23.1; npm 10.9.8; Python 3.12.3.
- DDGS 9.14.4 in the pinned Hermes virtual environment.

## Paperclip remediations

1. `paperclip-2026.720.0-hermes-local-api-url.patch`: makes the adapter honor configured `paperclipApiUrl` instead of overwriting it with the host listener URL. Affects `@paperclipai/hermes-paperclip-adapter/dist/server/execute.js`.
2. `paperclip-2026.720.0-session-fingerprint.patch`: removes volatile timestamp fields from the effective run fingerprint so valid sessions are not reset each heartbeat. Affects the server effective-run-config fingerprint module.
3. `paperclip-2026.720.0-onboarding-assets/`: restores five files omitted from the installed `@paperclipai/server 2026.720.0` package using byte-identical files from the local npm cache for the same version. Loader test passed for default (1 file) and CEO (4 files) bundles.
4. `paperclip-2026.720.0-hermes-safe-api-client.patch`: instructs Hermes prompts to use the FD-based API client instead of placing bearer values in command arguments.
5. `paperclip-2026.720.0-global-concurrency.patch`: adds a VM-wide heartbeat admission cap. `PAPERCLIP_HEARTBEAT_GLOBAL_MAX_CONCURRENT_RUNS=2` is enforced in addition to each employee's `maxConcurrentRuns=1`; a 12-agent live test must prove no more than two running, a queued state, and automatic promotion.

## Hermes remediations

1. `hermes-0.19.0-file-tools-docker-options.patch`: propagates configured Docker volumes/extra arguments to file tools.
2. `hermes-0.19.0-checkpoint-docker-bind.patch`: maps Docker workspace paths to the host bind root for checkpoint creation/restoration.
3. `hermes-0.19.0-docker-interrupt-cleanup.patch`: stops a shared persistent container before killing an interrupted `docker exec`, preventing descendants from surviving timeout/SIGTERM.
4. `hermes-0.19.0-paperclip-sync-delegation.patch`: `HERMES_FORCE_SYNC_DELEGATION=1` makes model-triggered one-shot delegation synchronous while preserving concurrent batch children, preventing parent exit from cancelling children.
5. `hermes-0.19.0-web-search-codex-alias.patch`: adds `web_search_hermes`, an alias for the same configured backend, because the Codex Responses surface reserves/omits literal `web_search`.
6. `hermes-0.19.0-docker-profile-isolation.patch`: derives a stable short reuse identity from explicit external `HERMES_HOME` paths, preventing cross-agent persistent-container reuse.

Expected upstream and final SHA-256 values are in
`/opt/paperclip/integration/build/locks/overlays.tsv`; final overlays are in the
adjacent `overlays/` tree. Installation stops if upstream or final content
differs.

The installed `paperclip-integration-regression` command reruns 164 retained
Hermes tests covering file/checkpoint propagation, Docker interruption and
profile reuse, synchronous delegation, shared child-container identity, the
web-search alias, and session behavior. It also executes direct Paperclip
adapter-URL and session-fingerprint assertions. These are not a substitute for
the clean-VM release gates.

## Files created or modified

- `/etc/systemd/system/paperclip.service`
- `/etc/systemd/system/paperclip-health.service` and `.timer`
- `/etc/systemd/system/paperclip-backup.service` and `.timer`
- `/etc/systemd/system/paperclip-network-policy.service`
- `/etc/systemd/system/paperclip-soak-sample.service` and `.timer`
- `/etc/systemd/system/paperclip-offsite-sync.service` and `.timer`
- `/etc/docker/daemon.json`
- `/etc/paperclip/*` root-only environment/identity files
- `/opt/paperclip/ops/paperclip-health.sh`
- `/opt/paperclip/ops/paperclip-backup.sh`
- `/opt/paperclip/ops/paperclip-api` and `paperclip-board-api`
- `/opt/paperclip/ops/paperclip-emergency-control`
- `/opt/paperclip/ops/paperclip-network-policy`
- `/opt/paperclip/ops/paperclip-soak-sample.sh` and `paperclip-offsite-sync.sh`
- `/opt/paperclip/integration/**`
- Paperclip adapter/server installed files described above
- Hermes installed files described above
- `/var/lib/paperclip/agents/<core-role>/home/**`
- `/srv/paperclip/workspaces/<core-role>/**`
- Docker network `paperclip-hermes`
