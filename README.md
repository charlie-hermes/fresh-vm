# Fresh Hermes/Paperclip VM

This repository reproducibly builds the Hermes/Paperclip/Docker ecosystem from
a clean Ubuntu VM. It is the portable equivalent of a “golden image”: Git
stores the recipe, locked inputs, final source overlays, service definitions,
security policy, and acceptance tests—not the VM disk, credentials, database,
or machine identity.

The intended operator flow is deliberately small:

```bash
git clone https://github.com/charlie-hermes/fresh-vm.git
cd fresh-vm
sudo ./bootstrap.sh
sudo ./configure-secrets.sh /secure/path/hermes-auth.json /secure/path/offsite-backup.conf
sudo reboot
```

Reconnect, return to the clone, and run:

```bash
sudo ./verify.sh
```

Success is exactly:

```text
PLATFORM: PASS
FUNCTIONAL ACCEPTANCE: PASS
SECRET AUDIT: PASS
BACKUP: PASS
SYSTEMD FAILED UNITS: 0
PRODUCTION: READY
```

## Before installation

Create an Ubuntu 24.04 LTS amd64 VM with at least 4 vCPUs, a 12 GB-class RAM
allocation reporting at least 11,500,000 KiB in `/proc/meminfo`, and 30 GiB
free disk. This allowance accounts for hypervisor-reserved memory while
retaining capacity above the appliance's 10 GiB combined runtime ceilings.
Install Codex manually and clone this repository. The installer creates 2 GiB
swap if the VM has less than 1 GiB active swap.

Prepare, but do not put in this repository:

- a valid Hermes `auth.json`;
- two independently protected mounted remote filesystems: one for encrypted
  backups and one for the recovery-key escrow;
- an offsite configuration such as:

```ini
PAPERCLIP_OFFSITE_REQUIRED=true
PAPERCLIP_OFFSITE_MOUNT=/mnt/paperclip-offsite
PAPERCLIP_RECOVERY_ESCROW_MOUNT=/mnt/paperclip-key-escrow
```

Both mounts must already be supported remote filesystems, writable, and backed
by different remote sources when `configure-secrets.sh` runs. A root, local,
bind, or temporary filesystem does not count.

To give each client a distinct company name, use the optional first command:

```bash
sudo env PAPERCLIP_COMPANY_NAME="Client Name" ./bootstrap.sh
```

## What the build creates

- Paperclip `2026.720.0`, private and authenticated on `172.30.0.1:3100`;
- embedded PostgreSQL bound to `127.0.0.1:54329`;
- Hermes `0.19.0` at commit
  `7de554277de632364c74fcf8641daa58a9a977d9`;
- a digest-pinned Python/Node Docker sandbox and isolated Docker bridge;
- the eight approved Agency Core employees—Agency Director, Brand and Brief
  Steward, Search and Content Strategist, Content Producer, Search and Answer
  Optimiser, Editorial Integrity QA, Publishing Operator, and Growth
  Intelligence Analyst—each with a separate Hermes home, workspace, exact
  checksum-bound role bundle, persistent container identity, memory, and session;
- host firewall rules denying sandbox access to private/metadata networks,
  except the authenticated Paperclip route;
- encrypted local database/state backup, verified offsite replication,
  health/backup/soak timers, and emergency operations helpers.

Unique instance ID, hostname, JWT secret, Paperclip encryption key, backup
passphrase, administrator password, and board API key are generated on the
target. One-time operator details are stored root-only at
`/root/paperclip-firstboot-credentials`.

## The five phases

1. **Discover and lock.** `appliance.lock`, npm/uv locks, image digest, and
   `locks/overlays.tsv` define every material input.
2. **Build.** `bootstrap.sh` verifies the target, installs pinned runtimes and
   applications, applies checksum-guarded overlays, installs systemd/network
   policy, and creates a unique initialized appliance.
3. **Integrate secrets.** `configure-secrets.sh` validates and installs the
   provider credential, requires a real off-host mount, makes a fresh encrypted
   backup, verifies replication, and records the pre-reboot boot ID.
4. **Reboot and accept.** `verify.sh` requires a new boot, then makes all eight
   Core profiles execute role-appropriate Paperclip tasks from reset sessions.
   It independently verifies exact Hermes `SOUL.md`/`AGENTS.md` loading,
   managed-instruction parity, denied toolsets, identity attribution, approved
   search, every workspace/container mount, socket isolation, comments,
   completion, and the VM-wide concurrency limit.
5. **Release.** The same command scans persisted files and run logs for actual
   credential values, decrypts and inventories a fresh backup, verifies the
   corresponding offsite copy and separately escrowed recovery key, runs the
   proprietary regression suite, checks every systemd unit, and emits the six
   release gates.

## Reproducibility and idempotency

The repository carries final overlays because the validated appliance includes
small local fixes beyond upstream releases. Every overlay has both an expected
upstream hash and a final hash. Installation stops on upstream drift instead of
applying a patch to unknown code.

The installer is safe to rerun after interruption. Once initialization is
complete it performs a platform verification and does not recreate the company,
employees, secrets, or state. Package upgrades are held because unattended
version drift would invalidate the appliance lock; upgrades should be tested by
changing the lock in a reviewed branch.

## Operations

Start with:

- `docs/architecture-security.md`
- `docs/core-role-activation.md`
- `docs/operations-runbook.md`
- `docs/backup-restore.md`
- `docs/rollback.md`

Bootstrap logs are in `/var/log/paperclip-appliance/bootstrap.log`. Service
state is visible with:

```bash
sudo systemctl status paperclip.service paperclip-network-policy.service --no-pager
sudo systemctl --failed --no-pager
```

No repository file contains a production credential. Never add `auth.json`,
`.env`, offsite credentials, database state, acceptance evidence, or backups.
