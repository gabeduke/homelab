#!/bin/bash
# Install (or re-install) the k3s control plane.
#
# ALL configuration lives in /etc/rancher/k3s/config.yaml, not INSTALL_K3S_EXEC.
# This is deliberate and load-bearing: k3s CLI flags override config-file values,
# and for repeatable args such as tls-san "the CLI arguments will overwrite all
# values in the list". So while the systemd unit carries a --tls-san= flag, any
# tls-san in config.yaml is ignored entirely -- writing the config file and
# restarting would appear to work and silently change nothing.
#
# Keeping the unit's ExecStart at bare `server` is what lets ip.sh update the
# public IP later without re-running this installer. See
# docs/plans/03-k3s-config-migration.md.
set -euo pipefail

EXTRA_SAN="${1:-$(hostname)}"
IP="$(hostname --all-ip-addresses | awk '{print $1}')"

# A re-run must never silently change the k3s version. On an existing node we
# pin to whatever is already installed; upgrades are system-upgrade-controller's
# job (plan 05). Set K3S_VERSION explicitly for a deliberate first install.
#
# Without this, the hourly IP cron reinstalled `stable` on every ISP lease
# change: on 2026-04-25 at 05:00 it pulled v1.34.6+k3s1 and restarted the
# control plane, undrained and unreviewed.
if command -v k3s >/dev/null 2>&1; then
    INSTALL_K3S_VERSION="$(k3s --version | awk '/^k3s version/ {print $3}')"
else
    INSTALL_K3S_VERSION="${K3S_VERSION:?set K3S_VERSION for a first install, e.g. v1.36.4+k3s1}"
fi
export INSTALL_K3S_VERSION
echo "==> pinning k3s to ${INSTALL_K3S_VERSION}"

sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml >/dev/null <<EOF
# Managed by scripts/control-plane/run.sh. Static configuration only -- the
# public IP is a separate drop-in that ip.sh rewrites.
write-kubeconfig-mode: "0644"
node-taint:
  - "node-role.kubernetes.io/control-plane=true:NoSchedule"
advertise-address: "${IP}"
tls-san:
  - "${EXTRA_SAN}"
  - "${IP}"
# k3s ships local-path as a StorageClass annotated is-default-class=true from a
# bundled manifest, and Longhorn marks its class default too -- two defaults,
# chosen between arbitrarily for any PVC omitting storageClassName. A kubectl
# patch does not hold: the addon controller re-applies on upgrade. Every PVC
# here uses Longhorn, and local-path cannot expand and pins data to one node.
disable:
  - local-storage
EOF

# The public IP lives in a drop-in that ip.sh owns; seed it if absent. Drop-ins
# are read after config.yaml in alphabetical order, and the `+` suffix appends
# to the list rather than replacing it -- so this adds the public IP to the
# static SANs above instead of clobbering them.
if [ ! -f /etc/rancher/k3s/config.yaml.d/10-external-ip.yaml ]; then
    sudo mkdir -p /etc/rancher/k3s/config.yaml.d
    EXTERNAL_IP="$(dig +short myip.opendns.com @resolver1.opendns.com)"
    sudo tee /etc/rancher/k3s/config.yaml.d/10-external-ip.yaml >/dev/null <<EOF
# Managed by ip.sh -- rewritten when the ISP lease changes. Do not hand-edit.
tls-san+:
  - "${EXTERNAL_IP}"
node-external-ip: "${EXTERNAL_IP}"
EOF
fi

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -
