#!/bin/bash
# Hourly from cron on the control plane. When the ISP lease changes, refresh the
# public IP in the k3s config and re-issue the API server certificate.
#
# This deliberately does NOT re-run the k3s installer. The previous version did
# (`sh run.sh` with no arguments), which had two consequences on every lease
# change: ${1} expanded empty so the node hostname was dropped from --tls-san,
# and `curl | sh` installed whatever the stable channel resolved to at that
# moment -- undrained, unreviewed, at whatever hour the lease happened to change.
# Confirmed to have fired on 2026-04-25 05:00 (installed v1.34.6+k3s1).
#
# k3s does not need a reinstall to learn a new SAN: change the config, discard
# the cached serving cert, restart. See docs/plans/03-k3s-config-migration.md.
set -euo pipefail

LOG_DIR="/home/gabeduke/log"
IPS_LOG="${LOG_DIR}/ips.log"
DROPIN="/etc/rancher/k3s/config.yaml.d/10-external-ip.yaml"

mkdir -p "${LOG_DIR}"
touch "${IPS_LOG}"

# On every run, changed IP or not, make each LoadBalancer Service's published
# IPs match the nodes' current external IPs. k3s servicelb only recomputes a
# Service's status.loadBalancer when its svclb pods change, so after a lease
# change, and after the agents' own hourly ip.sh restarts, it keeps advertising
# the old IP and external-dns keeps publishing it (seen 2026-10-11). Workers
# refresh on their own cron, so this converges within an hour of the last node
# updating. Best effort: bounded by timeouts, never fails the script.
reconcile_svclb() {
    local k="sudo timeout 30 k3s kubectl"
    local node_ips
    node_ips="$(${k} get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="ExternalIP")].address}{"\n"}{end}' 2>/dev/null | sort -u | xargs)" || return 0
    [ -n "${node_ips}" ] || return 0
    ${k} get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace} {.metadata.name} {.status.loadBalancer.ingress[*].ip}{"\n"}{end}' 2>/dev/null \
      | while read -r ns name lb_ips; do
            lb_ips="$(echo "${lb_ips}" | tr ' ' '\n' | sort -u | xargs)"
            [ "${lb_ips}" = "${node_ips}" ] && continue
            echo "$(date): ${ns}/${name} publishes '${lb_ips}', nodes are '${node_ips}'; restarting its svclb"
            ${k} -n kube-system rollout restart ds \
              -l "svccontroller.k3s.cattle.io/svcname=${name},svccontroller.k3s.cattle.io/svcnamespace=${ns}" \
              || echo "$(date): svclb restart for ${ns}/${name} failed"
        done || true
}
trap reconcile_svclb EXIT

# dig prints its retries on stdout before the answer: a slow resolver gives
# ";; communications error to ...#53: timed out" lines and then the address.
# Keep the last line only.
CURRENT_IPV4="$(dig +short +tries=3 +time=5 myip.opendns.com @resolver1.opendns.com 2>/dev/null | tail -1 || true)"
LAST_IPV4="$(tail -1 "${IPS_LOG}" | awk -F, '{print $2}')"

# A failed lookup must not be mistaken for a new address. Without this, a DNS
# blip would restart k3s and write garbage into the SAN list.
#
# The whole value is matched, not each line: on 2026-10-08 01:00 a retry line
# plus the address passed a line-by-line grep, the multi-line string went into
# node-external-ip, and k3s sat in "activating" for two days.
if ! [[ "${CURRENT_IPV4}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "$(date): could not resolve public IP (got '${CURRENT_IPV4}') -- skipping"
    exit 0
fi

if [ "${CURRENT_IPV4}" = "${LAST_IPV4}" ]; then
    echo "$(date): IP unchanged (${CURRENT_IPV4})"
    exit 0
fi

echo "$(date): IP changed ${LAST_IPV4:-<none>} -> ${CURRENT_IPV4}; re-issuing API cert"
echo "$(date),${CURRENT_IPV4}" >> "${IPS_LOG}"

sudo mkdir -p "$(dirname "${DROPIN}")"
sudo tee "${DROPIN}" >/dev/null <<EOF
# Managed by ip.sh -- rewritten when the ISP lease changes. Do not hand-edit.
tls-san+:
  - "${CURRENT_IPV4}"
node-external-ip: "${CURRENT_IPV4}"
EOF

# k3s caches the SAN set in both of these and will not pick up a new one until
# they are cleared.
#
# This does NOT prune stale SANs, despite deleting the secret. k3s re-seeds the
# listener secret from the on-disk serving-kube-apiserver.crt, so entries only
# ever accumulate -- by 2026-09 the cert carried five dead public IPs. That is
# harmless (extra SANs on a cert whose key never leaves the node) and is in fact
# the reason the old reinstall bug never caused an outage: when it dropped
# `alphapi` from --tls-san on 2026-04-25, the cached cert kept serving it.
# To actually prune, also remove serving-kube-apiserver.{crt,key} -- deliberately
# not done here, since regenerating that cert is a bigger blast radius than a
# lease change warrants.
#
# The delete needs the API server, which may be the thing that's down -- it was
# on 2026-10-08 02:00, and under set -e its failure skipped the restart that
# would have brought it back. Best effort, bounded; the restart always runs.
sudo timeout 20 k3s kubectl -n kube-system delete secret k3s-serving --ignore-not-found \
  || echo "$(date): couldn't delete k3s-serving (API down?); restarting anyway"
sudo rm -f /var/lib/rancher/k3s/server/tls/dynamic-cert.json
sudo systemctl restart k3s

echo "$(date): k3s restarted; new SANs:"
sleep 20
echo | openssl s_client -connect 127.0.0.1:6443 2>/dev/null \
  | openssl x509 -noout -text | grep -A3 'Subject Alternative Name' || true
