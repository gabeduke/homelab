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

# KNOWN LIMITATION: unlike the control plane, an agent's --node-external-ip is
# never refreshed -- only alphapi runs the IP cron, so all three nodes keep
# advertising whatever public IP was current at join time. On a single-homed
# home network this has not mattered. If it ever does, give the agents the same
# /etc/rancher/k3s/config.yaml.d drop-in the control plane uses.
export INSTALL_K3S_EXEC="--node-external-ip=${EXTERNAL_IP}"

curl -sfL https://get.k3s.io | K3S_TOKEN="${TOKEN}" sh -
