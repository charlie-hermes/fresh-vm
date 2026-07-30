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
emit files/systemd-dropins/tailscaled-paperclip-network-policy.conf \
  /etc/systemd/system/tailscaled.service.d/paperclip-network-policy.conf
while IFS= read -r source; do
  emit "$source" "/opt/paperclip/integration/${source#files/}"
done < <(find files/factory files/paperclip docs -type f | sort)
emit scripts/functional-acceptance.sh /opt/paperclip/ops/functional-acceptance.sh
emit scripts/profile-init /usr/local/sbin/paperclip-hermes-profile-init
emit scripts/credential-install /usr/local/sbin/paperclip-hermes-credential-install
emit scripts/core-role-transition /usr/local/sbin/paperclip-core-role-transition
emit scripts/runtime-bundle-verify /opt/paperclip/ops/runtime-bundle-verify
emit scripts/agency-os-install /usr/local/sbin/agency-os-install
emit scripts/fleet-portal-install /usr/local/sbin/fleet-portal-install
emit scripts/fleet-portal-configure /usr/local/sbin/fleet-portal-configure
emit scripts/fleet-portal-mutations /usr/local/sbin/fleet-portal-mutations
emit scripts/fleet-portal-paperclip-sync /usr/local/sbin/fleet-portal-paperclip-sync
emit scripts/fleet-portal-credential-provision /usr/local/sbin/fleet-portal-credential-provision
emit scripts/fleet-portal-external-verify /usr/local/sbin/fleet-portal-external-verify
emit scripts/fleet-portal-prepare-approval /usr/local/sbin/fleet-portal-prepare-approval
emit verify.sh /usr/local/sbin/paperclip-appliance-verify
emit appliance.lock /opt/paperclip/integration/build/appliance.lock
