# Backup and restore

## Optional tooling

Backups are not created, scheduled, or required by this project. VM snapshots,
backups, and recovery are managed by the human VM owner.

The bundled backup service is retained only for optional manual use. Before
using it, the owner must create and protect its encryption passphrase.

Manual backup:

```sh
sudo systemctl start paperclip-backup.service
sudo systemctl status paperclip-backup.service --no-pager
sudo find /var/lib/paperclip/backups -maxdepth 2 -type f -printf '%TY-%Tm-%Td %TT %s %p\n' | sort
```

## Contents

- Consistent Paperclip SQL/database backup from `paperclipai db:backup`.
- Full non-database instance state, including managed instructions and metadata; transient instance logs are excluded.
- All eight active Core Hermes employee homes, plus retained paused legacy
  homes during an upgrade: sessions, SQLite state, memory, checkpoints, skill
  state, and sandbox-home state.
- All employee workspaces and acceptance evidence.
- Systemd units, Docker daemon config, operations scripts and integration/patch documentation.
- Non-secret instance/company/employee identity mappings required to reconnect
  the restored database and active Core profile identity map.

Excluded from plaintext state archives:

- Embedded live database directory (the consistent SQL backup is authoritative).
- Backup directories (no recursion).
- The instance `.env` and transient `instances/default/logs` tree.
- Each Hermes `auth.json`, `.env`, and logs.
- Root-owned `/etc/paperclip` secrets.
- Browser binaries/caches and pinned application runtimes; reinstall them from the documented pins.

Any optional backup of provider or operator credentials, encryption keys, and
recovery material is the human VM owner's responsibility. The project verifier
does not inspect or require it.

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

1. Record current versions and follow the human VM owner's recovery process.
2. Stop Paperclip; keep Docker stopped if restoring sandbox state.
3. Reinstall the exact Paperclip/Hermes/runtime pins and local patches from `/opt/paperclip/integration`.
4. Restore the state archive to `/` as root, preserving numeric owners.
5. Restore provider/operator credentials from encrypted storage or reauthenticate; enforce modes 0600 and correct owners.
6. This build has no `db:restore` CLI. Provision a clean target PostgreSQL database and invoke `runDatabaseRestore({ connectionString, backupFile })` from `@paperclipai/db/backup-lib`; never point it at the live source database. The verified non-production pattern uses `startEmbeddedPostgresTestDatabase` from `@paperclipai/db` and always calls its `cleanup()` method.
7. Run `systemctl daemon-reload`; start Docker/containerd and Paperclip.
8. Verify health, listeners, private route, agents, workspaces, session/memory/checkpoint state, container labels/mounts, and one real heartbeat.

Record restore-test evidence outside the appliance repository and never claim a
restore test that was not performed on the client instance.
