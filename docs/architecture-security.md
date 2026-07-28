# Architecture and security boundary

## Runtime flow

1. `paperclip.service` runs as the non-login `paperclip` account.
2. Paperclip's embedded PostgreSQL listens only on `127.0.0.1:54329`.
3. Paperclip listens only on Docker bridge gateway `172.30.0.1:3100`; it is not bound to a public or wildcard host address.
4. A heartbeat spawns the pinned Hermes CLI locally through `hermes_local`.
5. Hermes uses the host for model calls, agent-specific sessions/memory/checkpoints, approved skill metadata, delegation orchestration, and the constrained web-search provider. Host browser, cron, and clarification toolsets are disabled for employee profiles.
6. Terminal, file-manipulation, and code-execution tool handlers use the Docker backend and fail closed if Docker is unavailable.
7. Containers call Paperclip at `http://paperclip-host:3100` through bridge `paperclip-hermes` and an explicit `paperclip-host:172.30.0.1` host mapping.

No Hermes Gateway service exists and no `hermes_gateway` fallback is configured.

## Identity and privilege

- Account: system user `paperclip`, system-assigned UID/GID, home
  `/var/lib/paperclip`, shell `/usr/sbin/nologin`.
- Supplementary group: `docker`. Docker socket membership is root-equivalent;
  the operator explicitly authorizes this risk by running the installer.
- Normal login user was not added to `docker`.
- Paperclip uses `NoNewPrivileges`, an empty capability bounding set, restrictive systemd filesystem/kernel controls, `UMask=0077`, `MemoryMax=4G`, and `TasksMax=2048`.
- Rootful Docker was retained because it is the installed/tested Hermes backend; rootless Docker was not adopted without full backend compatibility evidence.

## Per-agent state

The appliance creates exactly eight active Core profiles: `agency-director`,
`brand-brief-steward`, `search-content-strategist`, `content-producer`,
`search-answer-optimiser`, `editorial-integrity-qa`, `publishing-operator`, and
`growth-intelligence-analyst`. Each uses:

- Hermes home: `/var/lib/paperclip/agents/<slug>/home`
- Workspace: `/srv/paperclip/workspaces/<slug>`
- A reuse identity derived from its explicit `HERMES_HOME`

A local Hermes 0.19.0 fix hashes explicit external `HERMES_HOME` paths into the container reuse label. Without it, distinct external homes were both labeled `default` and could reuse the other agent's mounts. Post-patch Docker inspection and mutually exclusive sentinels proved separation.

## Docker boundary

Immutable image:

`nikolaik/python-nodejs@sha256:8f958bdc1b4a422bfafd97cab4f69836401f616ae985d4b57a53d254f5bcb038`

Network: bridge `paperclip-hermes`, subnet `172.30.0.0/24`, gateway `172.30.0.1`, inter-container communication disabled. Host networking is not used.

Per-profile mounts:

- `/srv/paperclip/workspaces/<slug>:/workspace` read-write.
- `/var/lib/paperclip/agents/<slug>/home/skills:/root/.hermes/skills` read-only.
- `/var/lib/paperclip/agents/<slug>/home/sandboxes/docker/<task>/home:/root` read-write.
- Delegation cache is mounted read-only where required.

All employees use the same layout under their own homes/workspaces. `/`, host
home directories, host PID namespace, and `/run/docker.sock` are never mounted.
Containers are not privileged, drop all capabilities, add only `CHOWN`,
`DAC_OVERRIDE`, and `FOWNER`, use `no-new-privileges`, PID 256, CPU 2, memory
3 GiB, bounded tmpfs, and 120-second command timeout. The root filesystem
remains writable because package/code workloads require it; durable state
belongs in approved bind mounts.

The bridge denies inter-container communication. `DOCKER-USER` denies access from `172.30.0.0/24` to RFC1918, loopback, link-local/metadata, and carrier-grade NAT ranges; the host input policy permits only TCP 3100 from the bridge and rejects other host services. Public HTTPS and DNS remain available. Live probes confirmed Paperclip and public egress succeed while metadata, host SSH, and PostgreSQL fail.

The configured 10 GiB container disk target is not enforceable by Docker
overlayfs. Disk safety instead requires at least 30 GiB free at installation,
10 MiB × 3 container log rotation and the one-minute health check's 85% disk
threshold.

## Capability boundary

| Capability | Execution boundary | Evidence |
|---|---|---|
| Terminal | Docker | `pwd=/workspace`, cgroup/mount inspection, fail-closed Docker tests |
| File tools | Docker | exact writes/readbacks in approved workspace; host sentinel inaccessible |
| Code execution | Docker | exact code readback and Docker environment evidence |
| Browser | Disabled for employee profiles | removed from role toolsets to avoid a host-side browsing path |
| Web search | Host child under hardened service | DDGS via `web_search_hermes`; native extraction unavailable with DDGS |
| MCP | Host stdio/HTTP child under hardened service | local echo server passed, then was unregistered |
| Role context and skills | Exact checksum-bound SOUL/AGENTS bundle plus the common Paperclip employee skill; actions still follow the Docker boundary | eight fresh-process load proofs, managed-instruction parity, and eight live role certifications |
| Delegation | Host orchestration; child terminal/file/code tools use Docker | parallel child collision test passed after sync-lifecycle patch |
| Memory/sessions/checkpoints | Agent-specific host profile | cross-process recall, resume, checkpoint restore passed |

## Secrets

- Root-owned operator files: `/etc/paperclip/operator.env` and related IDs, mode 0600.
- Provider credentials: each Hermes profile's `auth.json`/`.env`, mode 0600, excluded from plaintext backups.
- Paperclip injects run-scoped identity variables; only the explicit Paperclip API variables are forwarded to Docker. `docker_env` is empty and provider credentials are not forwarded.
- The API key is not stored in agent configuration, prompts, units, images, or reports and was tested by boolean/authenticated requests without printing it.
- Employee API calls use the reviewed `/opt/paperclip/ops/paperclip-api` client, which supplies the bearer value over file descriptor 3 rather than argv. The root board client is operator-only.

## Remaining limitations

- Docker group membership is root-equivalent.
- Employee browser automation is intentionally disabled. DDGS provides constrained search only; adding extraction or browsing requires a fresh host-network and prompt-injection review.
- DDGS provides search only. Use browser tools for extraction or configure a supported extraction provider.
- Only OpenAI Codex OAuth is configured. Hermes' provider-routing framework remains available, but failover cannot be live-tested without a second credential.
- OpenAI Codex OAuth reports token counters and subscription-included cost (`0.0`), not a metered dollar charge.
- Persistent containers are shared only within the same agent-home/task identity. Concurrent mutation of one shared workspace/package tree still requires per-task worktrees or separate profiles.
- Docker membership makes the `paperclip` service account root-equivalent. Network and systemd restrictions reduce accidental exposure but do not make Docker socket access a security boundary against a compromised service account.
- VM snapshots, backups, and recovery are controlled by the human VM owner.
  They are outside the appliance release checks and do not affect runtime
  acceptance.
- On full VM shutdown, Paperclip 2026.720.0 may log a graceful-run-drain query warning if its embedded PostgreSQL socket closes first. The accepted reboot had zero active runs, clean systemd deactivation, healthy database recovery, and a successful post-boot production heartbeat; treat the warning as an ordering limitation and confirm no active runs before planned reboot.
