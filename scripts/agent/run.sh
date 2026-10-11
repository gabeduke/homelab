#!/bin/bash
# Join a worker node to the k3s control plane.
set -euo pipefail

TOKEN="${1:?node token required}"
ADVERTISE_IP="${2:?control-plane IP required}"
EXTERNAL_IP="${3:?external IP required}"

# Same rule as the control plane: a re-run must never silently change the k3s
# version. Upgrades belong to system-upgrade-controller (plan 05).
if command -v k3s >/dev/null 2>&1; then
    INSTALL_K3S_VERSION="$(k3s --version | awk '/^k3s version/ {print $3}')"
else
    INSTALL_K3S_VERSION="${K3S_VERSION:?set K3S_VERSION for a first install, e.g. v1.36.4+k3s1}"
fi
export INSTALL_K3S_VERSION
echo "==> pinning k3s to ${INSTALL_K3S_VERSION}"

export K3S_URL="https://${ADVERTISE_IP}:6443"

# The public IP goes in the drop-in that ip.sh (hourly cron, `make setup-cron`)
# keeps current -- NOT on the command line, which would override the drop-in and
# freeze the join-time IP. That is what left betapi/charliepi advertising a dead
# IP after the 2026-10-08 lease change.
sudo mkdir -p /etc/rancher/k3s/config.yaml.d
sudo tee /etc/rancher/k3s/config.yaml.d/10-external-ip.yaml >/dev/null <<EOF
# Managed by ip.sh -- rewritten when the ISP lease changes. Do not hand-edit.
node-external-ip: "${EXTERNAL_IP}"
EOF
export INSTALL_K3S_EXEC="agent"

curl -sfL https://get.k3s.io | K3S_TOKEN="${TOKEN}" sh -
