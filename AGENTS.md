# Codex execution contract

## Objective

Turn one clean, manually created Ubuntu 24.04 amd64 VM into the locked
Hermes/Paperclip/Docker appliance defined by this repository. Completion means
`sudo ./verify.sh` prints all six release gates:

```text
PLATFORM: PASS
FUNCTIONAL ACCEPTANCE: PASS
SECRET AUDIT: PASS
BACKUP: PASS
SYSTEMD FAILED UNITS: 0
PRODUCTION: READY
```

Do not claim completion if any line is absent.

## Supported target

- Ubuntu 24.04 LTS (`noble`), amd64.
- At least 4 vCPUs, 12 GiB RAM, and 30 GiB free on `/`.
- Internet access to Ubuntu, NodeSource, npm, GitHub, Python package indexes,
  and the Docker registry during installation.
- Codex is already installed by the operator.
- This repository is cloned onto the target VM.

`bootstrap.sh` deliberately refuses a different platform or insufficient
capacity. Do not bypass those checks.

## Required operator inputs

Two secrets/integrations are intentionally absent from Git:

1. A valid Hermes `auth.json`, supplied by an absolute path to a root-readable
   regular file.
2. A root-readable offsite configuration naming two different, currently
   mounted remote filesystems: encrypted backup storage and independent
   recovery-key escrow.

If the operator has not supplied both paths, run only the bootstrap and then
ask for those two paths. Never paste their contents into chat, a command line,
Git, logs, or issue comments.

## Execution

From the repository root:

```bash
sudo ./bootstrap.sh
sudo ./configure-secrets.sh /secure/path/hermes-auth.json /secure/path/offsite-backup.conf
sudo reboot
```

After reconnecting to the same VM:

```bash
cd /path/to/fresh-vm
sudo ./verify.sh
```

The scripts are intentionally idempotent. If an installation is interrupted,
fix the reported external cause and rerun the same command. Do not delete
Paperclip state, regenerate credentials, change pins, loosen security controls,
or replace an acceptance gate to make a rerun pass.

## Non-negotiable controls

- Use the versions and digests in `appliance.lock`.
- Verify the repository manifest and all upstream/final overlay checksums.
- Keep Paperclip private on `172.30.0.1:3100`; keep PostgreSQL on loopback.
- Never expose or mount the Docker socket into a Hermes employee container.
- Preserve one isolated Hermes home and workspace per employee.
- Preserve strict local secret encryption, JWT legacy-fallback denial, the
  Docker egress policy, global concurrency cap, encrypted backups, and required
  verified offsite replication.
- Post-reboot functional runs must be performed by all four employees and
  independently inspected from the host. Static checks alone are not
  acceptance.
- Never commit credentials, generated instance data, evidence, or backup
  artifacts.

## Failure handling

Read `/var/log/paperclip-appliance/bootstrap.log` and the failing systemd unit
before changing anything. The runbooks in `docs/` describe supported recovery.
If a pin is no longer retrievable or an upstream checksum differs, stop and
report supply-chain drift; do not silently install a newer release.
