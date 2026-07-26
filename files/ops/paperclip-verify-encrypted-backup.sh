#!/bin/sh
set -eu

backup_root=/var/lib/paperclip/backups
encrypted_dir=$backup_root/encrypted
encryption_key=/etc/paperclip/backup-encryption.passphrase
export GNUPGHOME=$backup_root/.gnupg
state_file=${1:-$(find "$encrypted_dir" -maxdepth 1 -type f -name 'state-*.tar.gz.gpg' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)}
database_file=${2:-$(find "$encrypted_dir" -maxdepth 1 -type f -name 'database-*.sql.gz.gpg' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)}

test -n "$state_file" && test -f "$state_file"
test -n "$database_file" && test -f "$database_file"
test -r "$encryption_key"
sha256sum -c "$state_file.sha256"
sha256sum -c "$database_file.sha256"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$encryption_key" --output "$work_dir/state.tar.gz" --decrypt "$state_file"
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$encryption_key" --output "$work_dir/database.sql.gz" --decrypt "$database_file"
tar -tzf "$work_dir/state.tar.gz" >"$work_dir/inventory"
gzip -t "$work_dir/database.sql.gz"
grep -qx 'var/lib/paperclip/instances/default/config.json' "$work_dir/inventory"
grep -qx 'var/lib/paperclip/instances/default/secrets/master.key' "$work_dir/inventory"
grep -q '/skills/paperclip-employee/SKILL.md$' "$work_dir/inventory"
if grep -Eq '/home/(auth\.json|\.env)$|/home/logs/' "$work_dir/inventory"; then
  echo "Credential or log path unexpectedly present in encrypted state backup" >&2
  exit 1
fi
echo "Encrypted backup verification PASS"
