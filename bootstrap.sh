#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
umask 022

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$repo/appliance.lock"

test "$(id -u)" -eq 0 || { echo "Run with sudo: sudo ./bootstrap.sh" >&2; exit 77; }
exec 9>/run/lock/paperclip-appliance-bootstrap.lock
flock -n 9 || { echo "Another bootstrap is running" >&2; exit 75; }
install -d -o root -g root -m 0700 /var/log/paperclip-appliance
exec > >(tee -a /var/log/paperclip-appliance/bootstrap.log) 2>&1

die() { echo "BOOTSTRAP ERROR: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }
hash_is() { test "$(sha256sum "$1" | awk '{print $1}')" = "$2"; }

step "Validate repository and target VM"
test -f "$repo/MANIFEST.sha256" || die "MANIFEST.sha256 is required"
(cd "$repo" && sha256sum --check --strict MANIFEST.sha256) ||
  die "repository checksum validation failed"
# shellcheck disable=SC1091
. /etc/os-release
test "${ID:-}" = "$SUPPORTED_UBUNTU_ID" || die "Ubuntu is required"
test "${VERSION_ID:-}" = "$SUPPORTED_UBUNTU_VERSION" ||
  die "Ubuntu $SUPPORTED_UBUNTU_VERSION is required; found ${VERSION_ID:-unknown}"
test "${VERSION_CODENAME:-}" = "$SUPPORTED_UBUNTU_CODENAME" ||
  die "Ubuntu codename $SUPPORTED_UBUNTU_CODENAME is required"
test "$(dpkg --print-architecture)" = "$SUPPORTED_ARCH" ||
  die "$SUPPORTED_ARCH architecture is required"
test "$(nproc)" -ge "$MIN_CPU_COUNT" ||
  die "at least $MIN_CPU_COUNT vCPUs are required"
memory_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
test "$memory_kib" -ge "$MIN_MEMORY_KIB" ||
  die "at least $MIN_MEMORY_KIB KiB reported RAM (a 12 GB-class VM) is required"
root_free_kib=$(df -Pk / | awk 'NR==2 {print $4}')
test "$root_free_kib" -ge "$MIN_ROOT_FREE_KIB" ||
  die "at least 30 GiB free on / is required"

if [ -f /var/lib/paperclip-appliance/complete ]; then
  rm -f -- /var/lib/paperclip-appliance/pending
  rm -rf -- /var/lib/paperclip-appliance/bootstrap
  step "Existing initialized appliance detected"
  "$repo/verify.sh" --platform-only
  echo "Bootstrap is already complete; no state was recreated."
  exit 0
fi
if [ -f /var/lib/paperclip-appliance/precomplete ] &&
   [ ! -f /var/lib/paperclip-appliance/bootstrap/admin.env ]; then
  die "interrupted legacy initialization has no recovery credential; preserve state and follow the recovery runbook"
fi

step "Install pinned host prerequisites"
apt-get update
apt-get install --yes \
  build-essential ca-certificates curl file git gnupg gzip iproute2 iptables \
  jq libffi-dev libssl-dev mount openssl pkg-config python3 python3-dev \
  python3-venv tar util-linux xfsprogs

key_download=$(mktemp)
keyring_tmp=$(mktemp)
trap 'rm -f "$key_download" "$keyring_tmp"' EXIT HUP INT TERM
curl --fail --silent --show-error --location \
  https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key >"$key_download"
fingerprints=$(gpg --batch --show-keys --with-colons "$key_download" |
  awk -F: '$1=="fpr" {print $10}')
grep -qx "$NODESOURCE_PRIMARY_FINGERPRINT" <<<"$fingerprints" ||
  die "NodeSource primary signing-key fingerprint mismatch"
grep -qx "$NODESOURCE_SUBKEY_FINGERPRINT" <<<"$fingerprints" ||
  die "NodeSource signing-subkey fingerprint mismatch"
gpg --batch --yes --dearmor --output "$keyring_tmp" "$key_download"
install -o root -g root -m 0644 "$keyring_tmp" /usr/share/keyrings/nodesource.gpg
install -d -o root -g root -m 0755 /etc/apt/sources.list.d
printf '%s\n' \
  'Types: deb' \
  'URIs: https://deb.nodesource.com/node_22.x' \
  'Suites: nodistro' \
  'Components: main' \
  'Architectures: amd64' \
  'Signed-By: /usr/share/keyrings/nodesource.gpg' \
  >/etc/apt/sources.list.d/nodesource.sources
apt-get update
apt-get install --yes \
  "nodejs=$NODE_PACKAGE_VERSION" \
  "docker.io=$DOCKER_PACKAGE_VERSION" \
  "containerd=$CONTAINERD_PACKAGE_VERSION" \
  "runc=$RUNC_PACKAGE_VERSION"
test "$(node --version)" = "v$NODE_VERSION" || die "Node version mismatch"
apt-mark hold nodejs docker.io containerd runc >/dev/null

step "Provision host identity, service account, and swap"
getent group docker >/dev/null || groupadd --system docker
getent group paperclip >/dev/null || groupadd --system paperclip
if ! id paperclip >/dev/null 2>&1; then
  useradd --system --gid paperclip --groups docker --home-dir /var/lib/paperclip \
    --create-home --shell /usr/sbin/nologin paperclip
else
  usermod --append --groups docker paperclip
fi
swap_kib=$(awk 'NR>1 {total += $3} END {print total+0}' /proc/swaps)
if [ "$swap_kib" -lt 1048576 ]; then
  if [ ! -f /swapfile ]; then
    fallocate -l "${SWAP_SIZE_MIB}M" /swapfile
    chmod 0600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
  grep -qF '/swapfile none swap sw 0 0' /etc/fstab ||
    printf '%s\n' '/swapfile none swap sw 0 0' >>/etc/fstab
fi

step "Configure Docker and the isolated Hermes network"
install -d -o root -g root -m 0755 /etc/docker
install -o root -g root -m 0644 "$repo/files/docker/daemon.json" /etc/docker/daemon.json
systemctl enable --now containerd.service docker.service
systemctl restart docker.service
if docker network inspect "$PAPERCLIP_NETWORK" >/dev/null 2>&1; then
  docker network inspect "$PAPERCLIP_NETWORK" |
    jq -e --arg subnet "$PAPERCLIP_SUBNET" --arg gateway "$PAPERCLIP_GATEWAY" \
      '.[0].Options["com.docker.network.bridge.enable_icc"]=="false" and
       .[0].IPAM.Config[0].Subnet==$subnet and
       .[0].IPAM.Config[0].Gateway==$gateway' >/dev/null ||
    die "existing $PAPERCLIP_NETWORK network does not match the locked specification"
else
  docker network create --driver bridge \
    --subnet "$PAPERCLIP_SUBNET" --gateway "$PAPERCLIP_GATEWAY" \
    --opt com.docker.network.bridge.enable_icc=false "$PAPERCLIP_NETWORK" >/dev/null
fi

step "Install Paperclip $PAPERCLIP_VERSION"
paperclip_root=/opt/paperclip/$PAPERCLIP_VERSION
install -d -o root -g root -m 0755 "$paperclip_root"
hash_is "$repo/locks/paperclip/package-lock.json" "$PAPERCLIP_PACKAGE_LOCK_SHA256" ||
  die "Paperclip lockfile checksum mismatch"
install -o root -g root -m 0644 "$repo/locks/paperclip/package.json" "$paperclip_root/package.json"
install -o root -g root -m 0644 "$repo/locks/paperclip/package-lock.json" "$paperclip_root/package-lock.json"
(cd "$paperclip_root" && npm ci --ignore-scripts --no-audit --no-fund)
"$repo/scripts/apply-overlays" "$repo" paperclip "$paperclip_root"
installed_paperclip=$(node -p \
  "require('$paperclip_root/node_modules/paperclipai/package.json').version")
test "$installed_paperclip" = "$PAPERCLIP_VERSION" ||
  die "Paperclip package version mismatch: $installed_paperclip"

step "Install Hermes $HERMES_VERSION at the locked commit"
hermes_root=/opt/hermes-agent/$HERMES_COMMIT
install -d -o root -g root -m 0755 /opt/hermes-agent
if [ ! -d "$hermes_root/.git" ]; then
  test ! -e "$hermes_root" || rmdir "$hermes_root"
  git clone --filter=blob:none "$HERMES_REPOSITORY" "$hermes_root"
fi
test "$(git -C "$hermes_root" remote get-url origin)" = "$HERMES_REPOSITORY" ||
  die "Hermes origin mismatch"
if ! git -C "$hermes_root" cat-file -e "$HERMES_COMMIT^{commit}" 2>/dev/null; then
  git -C "$hermes_root" fetch origin "$HERMES_COMMIT"
fi
git -C "$hermes_root" checkout --detach "$HERMES_COMMIT"
test "$(git -C "$hermes_root" rev-parse HEAD)" = "$HERMES_COMMIT"
hash_is "$hermes_root/uv.lock" "$HERMES_UV_LOCK_SHA256" ||
  die "Hermes uv.lock checksum mismatch"
hash_is "$hermes_root/pyproject.toml" "$HERMES_PYPROJECT_SHA256" ||
  die "Hermes pyproject checksum mismatch"
"$repo/scripts/apply-overlays" "$repo" hermes "$hermes_root"
python3 -m venv /opt/hermes-agent/uv-tool
/opt/hermes-agent/uv-tool/bin/pip install --disable-pip-version-check \
  --require-hashes --requirement "$repo/locks/uv.requirements.txt"
test "$(/opt/hermes-agent/uv-tool/bin/uv --version | awk '{print $2}')" = "$UV_VERSION" ||
  die "uv version mismatch"
(cd "$hermes_root" &&
  UV_PROJECT_ENVIRONMENT="$hermes_root/venv" \
    /opt/hermes-agent/uv-tool/bin/uv sync --locked --all-extras --dev)
/opt/hermes-agent/uv-tool/bin/uv pip install --no-deps --require-hashes \
  --python "$hermes_root/venv/bin/python" \
  --requirement "$repo/locks/hermes-ddgs.requirements.txt"
test "$("$hermes_root/venv/bin/python" -c \
  'from importlib.metadata import version; print(version("ddgs"))')" = "$DDGS_VERSION" ||
  die "DDGS version mismatch"
test "$("$hermes_root/venv/bin/hermes" --version |
  awk 'NR==1 {sub(/^v/,"",$3); print $3; exit}')" = "$HERMES_VERSION" ||
  die "Hermes CLI version mismatch"

step "Pull the digest-pinned Hermes sandbox image"
docker pull "$HERMES_DOCKER_IMAGE"
test "$(docker image inspect --format '{{.Id}}' "$HERMES_DOCKER_IMAGE")" = \
  "$HERMES_DOCKER_IMAGE_ID" || die "Hermes Docker image digest mismatch"

step "Install integration, operations, and systemd assets"
install -d -o root -g root -m 0755 \
  /opt/paperclip/integration /opt/paperclip/integration/docs \
  /opt/paperclip/integration/factory /opt/paperclip/integration/paperclip \
  /opt/paperclip/integration/build /opt/paperclip/ops
cp -a "$repo/docs/." /opt/paperclip/integration/docs/
cp -a "$repo/files/factory/." /opt/paperclip/integration/factory/
cp -a "$repo/files/paperclip/." /opt/paperclip/integration/paperclip/
cp -a "$repo/appliance.lock" "$repo/locks" "$repo/overlays" \
  /opt/paperclip/integration/build/
chown -R root:root /opt/paperclip/integration
find /opt/paperclip/integration -type d -exec chmod 0755 {} +
find /opt/paperclip/integration -type f -exec chmod 0644 {} +
find /opt/paperclip/integration/factory/skills -type f -path '*/scripts/*' \
  -exec chmod 0755 {} +

for script in "$repo"/files/ops/*; do
  install -o root -g root -m 0755 "$script" "/opt/paperclip/ops/$(basename "$script")"
done
install -o root -g root -m 0755 "$repo/files/bin/jq" /opt/paperclip/ops/jq
install -o root -g root -m 0755 "$repo/scripts/functional-acceptance.sh" \
  /opt/paperclip/ops/functional-acceptance.sh
install -o root -g root -m 0755 "$repo/scripts/profile-init" \
  /usr/local/sbin/paperclip-hermes-profile-init
install -o root -g root -m 0755 "$repo/scripts/credential-install" \
  /usr/local/sbin/paperclip-hermes-credential-install
install -o root -g root -m 0755 "$repo/scripts/core-role-transition" \
  /usr/local/sbin/paperclip-core-role-transition
install -o root -g root -m 0755 "$repo/scripts/runtime-bundle-verify" \
  /opt/paperclip/ops/runtime-bundle-verify
install -o root -g root -m 0755 "$repo/verify.sh" \
  /usr/local/sbin/paperclip-appliance-verify

for unit in "$repo"/files/systemd/*; do
  install -o root -g root -m 0644 "$unit" "/etc/systemd/system/$(basename "$unit")"
done
install -d -o root -g root -m 0755 /etc/systemd/system/paperclip.service.d
systemctl daemon-reload
systemctl enable paperclip.service paperclip-network-policy.service
systemctl start paperclip-network-policy.service

step "Initialize a unique private Paperclip appliance"
install -d -o root -g root -m 0700 /var/lib/paperclip-appliance
if [ ! -f /var/lib/paperclip-appliance/precomplete ] ||
   [ ! -f /var/lib/paperclip-appliance/complete ]; then
  touch /var/lib/paperclip-appliance/pending
  chmod 0600 /var/lib/paperclip-appliance/pending
fi
"$repo/scripts/initialize-pre"
systemctl enable --now paperclip.service
"$repo/scripts/initialize-finalize"

step "Bootstrap complete"
echo "The appliance is initialized with unique local secrets."
echo "Next: sudo ./configure-secrets.sh AUTH_JSON OFFSITE_CONFIG"
echo "Then reboot before running: sudo ./verify.sh"
