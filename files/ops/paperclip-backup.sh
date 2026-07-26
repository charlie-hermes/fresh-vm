#!/bin/sh
set -eu

backup_root=/var/lib/paperclip/backups
encrypted_dir=$backup_root/encrypted
encryption_key=/etc/paperclip/backup-encryption.passphrase
stamp=$(/usr/bin/date -u +%Y%m%d-%H%M%S)-$$
work_dir=/run/paperclip-backup/$stamp
database_dir=$work_dir/database
state_dir=$work_dir/state
export GNUPGHOME=$backup_root/.gnupg

/usr/bin/mkdir -p "$database_dir" "$state_dir" "$encrypted_dir" "$GNUPGHOME"
/usr/bin/chmod 0700 "$GNUPGHOME"
/usr/bin/test -r "$encryption_key" || { echo "Backup encryption key is not readable" >&2; exit 1; }
trap '/usr/bin/rm -rf -- "$work_dir"' EXIT HUP INT TERM

/opt/paperclip/2026.720.0/node_modules/.bin/paperclipai db:backup \
  --config /var/lib/paperclip/instances/default/config.json \
  --dir "$database_dir" \
  --retention-days 1 \
  --filename-prefix scheduled \
  --json

database_backup=$(/usr/bin/find "$database_dir" -maxdepth 1 -type f -name 'scheduled-*.sql.gz' -printf '%T@ %p\n' | /usr/bin/sort -nr | /usr/bin/head -n 1 | /usr/bin/cut -d' ' -f2-)
/usr/bin/test -n "$database_backup" || { echo "Database backup was not created" >&2; exit 1; }

# The SQL dump is the consistency-safe database copy. The state archive is
# dynamic so newly manufactured employee profiles and workspaces are included.
# Provider credentials and runtime logs are excluded before encryption.
archive=$state_dir/state-$stamp.tar.gz
/usr/bin/tar --create --gzip --file "$archive" \
  --numeric-owner \
  --exclude='var/lib/paperclip/backups' \
  --exclude='var/lib/paperclip/instances/default/db' \
  --exclude='var/lib/paperclip/instances/default/data/backups' \
  --exclude='var/lib/paperclip/instances/default/.env' \
  --exclude='var/lib/paperclip/instances/default/logs' \
  --exclude='var/lib/paperclip/agents/*/home/auth.json' \
  --exclude='var/lib/paperclip/agents/*/home/.env' \
  --exclude='var/lib/paperclip/agents/*/home/logs' \
  -C / \
  var/lib/paperclip/instances/default \
  var/lib/paperclip/agents \
  var/lib/paperclip/acceptance-evidence \
  srv/paperclip/workspaces \
  etc/systemd/system/paperclip.service \
  etc/systemd/system/paperclip.service.d \
  etc/systemd/system/paperclip-backup.service \
  etc/systemd/system/paperclip-backup.timer \
  etc/systemd/system/paperclip-health.service \
  etc/systemd/system/paperclip-health.timer \
  etc/systemd/system/paperclip-soak-sample.service \
  etc/systemd/system/paperclip-soak-sample.timer \
  etc/systemd/system/paperclip-offsite-sync.service \
  etc/systemd/system/paperclip-offsite-sync.timer \
  etc/paperclip/instance-id \
  etc/paperclip/offsite-backup.conf \
  etc/systemd/system/paperclip-network-policy.service \
  etc/docker/daemon.json \
  opt/paperclip/ops \
  opt/paperclip/integration \
  etc/paperclip/company-name \
  etc/paperclip/company-id \
  etc/paperclip/hermes-agent-id \
  etc/paperclip/hermes-agent-ids.json

/usr/bin/gpg --batch --yes --pinentry-mode loopback --passphrase-file "$encryption_key" \
  --symmetric --cipher-algo AES256 --compress-algo none \
  --output "$encrypted_dir/state-$stamp.tar.gz.gpg" "$archive"
/usr/bin/gpg --batch --yes --pinentry-mode loopback --passphrase-file "$encryption_key" \
  --symmetric --cipher-algo AES256 --compress-algo none \
  --output "$encrypted_dir/database-$stamp.sql.gz.gpg" "$database_backup"
/usr/bin/sha256sum "$encrypted_dir/state-$stamp.tar.gz.gpg" >"$encrypted_dir/state-$stamp.tar.gz.gpg.sha256"
/usr/bin/sha256sum "$encrypted_dir/database-$stamp.sql.gz.gpg" >"$encrypted_dir/database-$stamp.sql.gz.gpg.sha256"
/opt/paperclip/ops/paperclip-verify-encrypted-backup.sh \
  "$encrypted_dir/state-$stamp.tar.gz.gpg" \
  "$encrypted_dir/database-$stamp.sql.gz.gpg"
/usr/bin/find "$encrypted_dir" -type f -mtime +30 -delete

echo "Encrypted Paperclip backup created: $encrypted_dir/state-$stamp.tar.gz.gpg"
