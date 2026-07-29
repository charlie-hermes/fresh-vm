#!/bin/bash
set -Eeuo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
emit() {
  source=$1
  destination=$2
  printf '%s\t%s\t%s\n' "$(sha256sum "$source" | awk '{print $1}')" \
    "$source" "$destination"
}
for source in files/ops/*; do
  emit "$source" "/opt/paperclip/ops/${source##*/}"
done
for source in files/systemd/*; do
  emit "$source" "/etc/systemd/system/${source##*/}"
done
while IFS= read -r source; do
  emit "$source" "/opt/paperclip/integration/${source#files/}"
done < <(find files/factory files/paperclip docs -type f | sort)
emit scripts/functional-acceptance.sh /opt/paperclip/ops/functional-acceptance.sh
emit scripts/profile-init /usr/local/sbin/paperclip-hermes-profile-init
emit scripts/credential-install /usr/local/sbin/paperclip-hermes-credential-install
emit scripts/core-role-transition /usr/local/sbin/paperclip-core-role-transition
emit scripts/runtime-bundle-verify /opt/paperclip/ops/runtime-bundle-verify
emit scripts/agency-os-install /usr/local/sbin/agency-os-install
emit verify.sh /usr/local/sbin/paperclip-appliance-verify
emit appliance.lock /opt/paperclip/integration/build/appliance.lock
