#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d /tmp/fresh-vm-embedded-postgres.XXXXXX)
cleanup() {
  chmod -R u+w "$work" 2>/dev/null || true
  case "$work" in /tmp/fresh-vm-embedded-postgres.*) rm -rf -- "$work" ;; esac
}
trap cleanup EXIT HUP INT TERM

paperclip_root=$work/paperclip
lib_dir=$paperclip_root/node_modules/@embedded-postgres/linux-x64/native/lib
mkdir -p "$lib_dir"
touch "$lib_dir/libcrypto.so.1.1" "$lib_dir/libssl.so.1.1" \
  "$lib_dir/libpq.so.5.18" "$lib_dir/libz.so.1"
ln -s libpq.so.5.18 "$lib_dir/libpq.so.5"

"$repo/scripts/prepare-embedded-postgres-runtime" "$paperclip_root" >/dev/null
test "$(readlink "$lib_dir/libcrypto.so.1")" = libcrypto.so.1.1
test "$(readlink "$lib_dir/libssl.so.1")" = libssl.so.1.1
test "$(readlink "$lib_dir/libpq.so.5")" = libpq.so.5.18
test ! -e "$lib_dir/libz.so"

chmod a-w "$lib_dir"
"$repo/scripts/prepare-embedded-postgres-runtime" "$paperclip_root" >/dev/null
chmod u+w "$lib_dir"

rm "$lib_dir/libcrypto.so.1"
ln -s libssl.so.1.1 "$lib_dir/libcrypto.so.1"
if "$repo/scripts/prepare-embedded-postgres-runtime" "$paperclip_root" >/dev/null 2>&1; then
  echo "conflicting embedded PostgreSQL alias was accepted" >&2
  exit 1
fi

echo "EMBEDDED POSTGRES RUNTIME PASS"
