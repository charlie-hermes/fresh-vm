# Backup and restore

## Schedule and retention

`paperclip-backup.timer` runs daily with persistent catch-up. Paperclip's
built-in plaintext database backup is disabled. The integration backup stages
database and state data in a protected runtime directory, encrypts and verifies
both artifacts, removes the staging directory on every exit, and retains only
encrypted artifacts for 30 days.

Manual backup:

```sh
sudo systemctl start paperclip-backup.service
sudo systemctl status paperclip-backup.service --no-pager
sudo find /var/lib/paperclip/backups -maxdepth 2 -type f -printf '%TY-%Tm-%Td %TT %s %p\n' | sort
```

## Contents

- Consistent Paperclip SQL/database backup from `paperclipai db:backup`.
- Full non-database instance state, including managed instructions and metadata; transient instance logs are excluded.
- All four Hermes employee homes: sessions, SQLite state, memory, checkpoints,
  skill state, and sandbox-home state.
- Both workspaces and acceptance evidence.
- Systemd units, Docker daemon config, operations scripts and integration/patch documentation.
- Non-secret instance/company/employee identity mappings required to reconnect
  the restored database and four profiles.

Excluded from plaintext state archives:

- Embedded live database directory (the consistent SQL backup is authoritative).
- Backup directories (no recursion).
- The instance `.env` and transient `instances/default/logs` tree.
- Each Hermes `auth.json`, `.env`, and logs.
- Root-owned `/etc/paperclip` secrets.
- Browser binaries/caches and pinned application runtimes; reinstall them from the documented pins.

Provider and operator credentials require a separate encrypted backup or fresh
login/rotation. The backup-encryption passphrase is escrowed during every
offsite sync to the independently mounted recovery store. A production
commissioning pass fails if backup storage and key escrow resolve to the same
remote source.

Pre-fix state archives created before the instance `.env` and transient-log exclusions were added were deleted after a corrected archive validated. Generic token-signature scans may identify non-live placeholders in the bundled `native-mcp.md` skill reference; actual-value scans against live credentials must remain zero.

## Decrypt and validate an archive

```sh
restore_dir=$(mktemp -d /tmp/paperclip-restore.XXXXXX)
sudo gpg --batch --yes --pinentry-mode loopback \
  --passphrase-file /etc/paperclip/backup-encryption.passphrase \
  --output "$restore_dir/state.tar.gz" \
  --decrypt /var/lib/paperclip/backups/encrypted/state-YYYYMMDD-HHMMSS-PID.tar.gz.gpg
sudo tar -tzf "$restore_dir/state.tar.gz" | less
```

Assert that `auth.json`, all `.env` files, instance/profile logs, `/etc/paperclip`, and live `instances/default/db` are absent.

## State restore test pattern

Never restore over production during a test:

```sh
sudo tar -xzf "$restore_dir/state.tar.gz" -C "$restore_dir"
find "$restore_dir" -maxdepth 5 -type f | sort
```

Compare representative workspace, config, memory, session/checkpoint, unit, and patch hashes. Remove the temporary directory only after recording results.

## Production restore outline

1. Record current versions and make a fresh backup if readable.
2. Stop Paperclip; keep Docker stopped if restoring sandbox state.
3. Reinstall the exact Paperclip/Hermes/runtime pins and local patches from `/opt/paperclip/integration`.
4. Restore the state archive to `/` as root, preserving numeric owners.
5. Restore provider/operator credentials from encrypted storage or reauthenticate; enforce modes 0600 and correct owners.
6. This build has no `db:restore` CLI. Provision a clean target PostgreSQL database and invoke `runDatabaseRestore({ connectionString, backupFile })` from `@paperclipai/db/backup-lib`; never point it at the live source database. The verified non-production pattern uses `startEmbeddedPostgresTestDatabase` from `@paperclipai/db` and always calls its `cleanup()` method.
7. Run `systemctl daemon-reload`; start Docker/containerd and Paperclip.
8. Verify health, listeners, private route, agents, workspaces, session/memory/checkpoint state, container labels/mounts, and one real heartbeat.

Record restore-test evidence outside the appliance repository and never claim a
restore test that was not performed on the client instance.
