#!/bin/bash
# Hourly from cron on each worker. When the ISP lease changes, refresh this
# agent's node-external-ip and restart k3s-agent.
#
# The control plane's ip.sh does more (tls-san, the k3s-serving cert) and
# restarts the `k3s` unit; none of that applies to an agent, so this is its own
# script. Before it existed only alphapi was refreshed: after the 2026-10-08
# lease change betapi and charliepi kept advertising the dead 96.228.35.135,
# svclb and external-dns published it next to the real IP, and about half of
# all requests to *.leetserve.com hung.
#
# The IP must come from the drop-in, not the unit's ExecStart: a command-line
# flag overrides config files. migrate-external-ip.sh moves an existing agent.
set -euo pipefail

LOG_DIR="/home/gabeduke/log"
IPS_LOG="${LOG_DIR}/ips.log"
DROPIN="/etc/rancher/k3s/config.yaml.d/10-external-ip.yaml"
UNIT="/etc/systemd/system/k3s-agent.service"

mkdir -p "${LOG_DIR}"
touch "${IPS_LOG}"

if grep -q -- '--node-external-ip' "${UNIT}" 2>/dev/null; then
    echo "$(date): ${UNIT} still pins --node-external-ip on the command line, which overrides ${DROPIN}; run migrate-external-ip.sh first" >&2
    exit 1
fi

# Same lookup and whole-value check as the control plane's ip.sh; see the
# 2026-10-08 notes there for why both matter.
CURRENT_IPV4="$(dig +short +tries=3 +time=5 myip.opendns.com @resolver1.opendns.com 2>/dev/null | tail -1 || true)"
LAST_IPV4="$(tail -1 "${IPS_LOG}" | awk -F, '{print $2}')"

if ! [[ "${CURRENT_IPV4}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "$(date): could not resolve public IP (got '${CURRENT_IPV4}') -- skipping"
    exit 0
fi

if [ "${CURRENT_IPV4}" = "${LAST_IPV4}" ] && [ -f "${DROPIN}" ]; then
    echo "$(date): IP unchanged (${CURRENT_IPV4})"
    exit 0
fi

echo "$(date): IP changed ${LAST_IPV4:-<none>} -> ${CURRENT_IPV4}; restarting k3s-agent"
echo "$(date),${CURRENT_IPV4}" >> "${IPS_LOG}"

sudo mkdir -p "$(dirname "${DROPIN}")"
sudo tee "${DROPIN}" >/dev/null <<EOF
# Managed by ip.sh -- rewritten when the ISP lease changes. Do not hand-edit.
node-external-ip: "${CURRENT_IPV4}"
EOF

# Restarting the agent leaves running containers alone.
sudo systemctl restart k3s-agent
echo "$(date): k3s-agent restarted"
