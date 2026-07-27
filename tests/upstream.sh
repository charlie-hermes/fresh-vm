#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$repo/appliance.lock"
work=$(mktemp -d /tmp/fresh-vm-upstream.XXXXXX)
cleanup() {
  chmod -R u+w "$work" 2>/dev/null || true
  case "$work" in /tmp/fresh-vm-upstream.*) rm -rf -- "$work" ;; esac
}
trap cleanup EXIT HUP INT TERM

git clone --quiet --filter=blob:none --no-checkout "$HERMES_REPOSITORY" "$work/hermes"
git -C "$work/hermes" checkout --quiet --detach "$HERMES_COMMIT"
test "$(git -C "$work/hermes" rev-parse HEAD)" = "$HERMES_COMMIT"
test "$(sha256sum "$work/hermes/uv.lock" | awk '{print $1}')" = \
  "$HERMES_UV_LOCK_SHA256"
test "$(sha256sum "$work/hermes/pyproject.toml" | awk '{print $1}')" = \
  "$HERMES_PYPROJECT_SHA256"
"$repo/scripts/apply-overlays" "$repo" hermes "$work/hermes" >/dev/null

mkdir -p "$work/paperclip"
cp "$repo/locks/paperclip/package.json" \
  "$repo/locks/paperclip/package-lock.json" "$work/paperclip/"
test "$(sha256sum "$work/paperclip/package-lock.json" | awk '{print $1}')" = \
  "$PAPERCLIP_PACKAGE_LOCK_SHA256"
(cd "$work/paperclip" && npm ci --ignore-scripts --no-audit --no-fund >/dev/null)
"$repo/scripts/apply-overlays" "$repo" paperclip "$work/paperclip" >/dev/null
"$repo/scripts/prepare-embedded-postgres-runtime" "$work/paperclip" >/dev/null
native_lib=$work/paperclip/node_modules/@embedded-postgres/linux-x64/native/lib
test "$(readlink "$native_lib/libcrypto.so.1")" = libcrypto.so.1.1
test "$(readlink "$native_lib/libssl.so.1")" = libssl.so.1.1
chmod a-w "$native_lib"
node --input-type=module - \
  "$work/paperclip/node_modules/@paperclipai/db/dist/embedded-postgres-native.js" \
  "$native_lib" <<'NODE'
const [helper, libDir] = process.argv.slice(2);
const runtime = await import(`file://${helper}`);
const created = await runtime.ensureLinuxSharedLibraryAliases(libDir);
if (created.length !== 0) {
  throw new Error(`runtime helper created unexpected aliases: ${created.join(", ")}`);
}
NODE
chmod u+w "$native_lib"

while IFS=$'\t' read -r component _ final relative; do
  case "$component" in ""|\#*) continue ;; esac
  case "$component" in
    hermes) target="$work/hermes/$relative" ;;
    paperclip) target="$work/paperclip/$relative" ;;
    *) exit 1 ;;
  esac
  test "$(sha256sum "$target" | awk '{print $1}')" = "$final"
done <"$repo/locks/overlays.tsv"

echo "UPSTREAM REPRODUCIBILITY PASS"
