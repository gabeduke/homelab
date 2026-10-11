#!/bin/bash
# One-time, per worker: take --node-external-ip off the k3s-agent unit's
# ExecStart (where the installer put it and nothing ever refreshed it), then let
# ip.sh write the current IP to its drop-in and restart the agent. Safe to re-run.
set -euo pipefail

UNIT="/etc/systemd/system/k3s-agent.service"

if grep -q -- '--node-external-ip' "${UNIT}"; then
    sudo cp "${UNIT}" "${UNIT}.bak-external-ip"
    sudo sed -i '/--node-external-ip=/d' "${UNIT}"
    sudo systemctl daemon-reload
    echo "removed --node-external-ip from ${UNIT} (backup: ${UNIT}.bak-external-ip)"
fi

bash "$(dirname "$0")/ip.sh"
