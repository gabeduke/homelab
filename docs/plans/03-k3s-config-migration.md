# Plan 03 — Stop the IP cron from reinstalling k3s

**Finding:** S6-1 (plus S6-8) · **Risk: HIGH** — touches the live control plane
**Cluster impact:** one k3s restart · **Needs SSH:** yes
**Blocks:** nothing · **Blocked by:** nothing (but do 01 first, it is free)

This is the most consequential finding of the review and the one most likely to
have already caused an outage.

---

## The bug

`scripts/control-plane/ip.sh:19`, which runs **hourly from cron** on alphapi:

```bash
if [ "$CURRENT_IPV4" = "$LAST_IPV4" ]; then
    echo "$(date): IP has not changed ($CURRENT_IPV4)"
else
    echo "$(date): IP has changed to $CURRENT_IPV4"
    echo "$(date),$CURRENT_IPV4" >> "${IPS_LOG}"
    sh "${RUN_SCRIPT}"          # <-- /home/gabeduke/run.sh, no arguments
fi
```

`${RUN_SCRIPT}` is `control-plane/run.sh`. Called with **no arguments**, and that
script has `set -x` but no `set -eu`:

```bash
export INSTALL_K3S_EXEC="... --tls-san=${EXTERNAL_IP},${IP},${1} --disable local-storage"
curl -sfL https://get.k3s.io | sh -
```

Two separate failures, both triggered by an ISP lease change:

**1. `alphapi` is dropped from the API server certificate.** `${1}` is unset;
with no `set -u` it expands to empty, producing `--tls-san=<ext>,<internal>,` —
a trailing empty SAN and, critically, no `alphapi` hostname. Anything reaching
the API server by name then fails TLS verification. `docs/tls-http01-outage.md`
records exactly this class of outage in session 3.

**2. k3s is silently upgraded, undrained.** There is no `INSTALL_K3S_VERSION` or
`INSTALL_K3S_CHANNEL`, so `get.k3s.io` installs whatever `stable` resolves to at
that moment. No cordon, no drain, no review, at whatever hour the lease changes.

This is almost certainly how the cluster reached v1.35.5 while
`system-upgrade-controller` has never been installed (plan 05 — the namespace is
empty and the `Plan` CRD does not exist).

### Confirm before fixing

Not verified live — SSH was unavailable during the review.

```bash
ssh gabeduke@alphapi 'crontab -l'                    # expect the @hourly ip.sh line
ssh gabeduke@alphapi 'tail -20 ~/log/ips.log'        # how often has the IP changed?
ssh gabeduke@alphapi 'tail -50 ~/log/ip-cron.log'    # look for installer output
ssh gabeduke@alphapi 'ls -la /var/lib/rancher/k3s/server/tls/dynamic-cert.json'
sudo k3s certificate check 2>/dev/null || \
  ssh gabeduke@alphapi "echo | openssl s_client -connect 127.0.0.1:6443 2>/dev/null | openssl x509 -noout -text | grep -A2 'Subject Alternative Name'"
```

That last command is the decisive one: **if `alphapi` is missing from the SAN
list, the bug has already fired.**

---

## Why the obvious fix is not enough

The tempting minimal fix is to pass the argument and pin the version:

```bash
sh "${RUN_SCRIPT}" "$(hostname)"     # + export INSTALL_K3S_VERSION
```

That closes both symptoms, but leaves an installer re-run — `curl | sh` piped
from the public internet — wired to an unattended cron trigger. k3s does not need
a reinstall to learn a new SAN.

**The documented approach** ([k3s docs](https://docs.k3s.io/cli/server),
[issue #2856](https://github.com/k3s-io/k3s/issues/2856)) is to change the config,
discard the cached serving cert, and restart:

```bash
sudo kubectl -n kube-system delete secret k3s-serving
sudo rm -f /var/lib/rancher/k3s/server/tls/dynamic-cert.json
sudo systemctl restart k3s
```

k3s regenerates the serving certificate with the new SAN list on startup. This is
non-destructive and takes about a minute.

### The catch that shapes the whole design

From the [k3s configuration docs](https://docs.k3s.io/installation/configuration):

> "values will be loaded from both sources, but CLI arguments will take precedence"

and for repeatable arguments such as `tls-san`:

> "the CLI arguments will overwrite **all** values in the list"

**So as long as `--tls-san=` stays in the systemd unit's `ExecStart`, any
`tls-san` in `config.yaml` is ignored entirely.** Writing a config file and
restarting would appear to work and silently change nothing.

The fix therefore has to move configuration **out of the unit and into
`config.yaml`**. That is the real work in this plan, and why it is rated high
risk despite being a small diff.

---

## Design

| Where | Owns | Changes when |
|---|---|---|
| `/etc/rancher/k3s/config.yaml` | static config: taint, advertise-address, disable list, static SANs | a rebuild (`run.sh` writes it) |
| `/etc/rancher/k3s/config.yaml.d/10-external-ip.yaml` | `tls-san+` and `node-external-ip` for the **public** IP | the ISP lease changes (`ip.sh` writes it) |
| systemd unit `ExecStart` | nothing but `server` | never |

Drop-ins are read after `config.yaml` in alphabetical order, and `+` appends to a
list rather than replacing it — so the drop-in adds the public IP to the static
SANs instead of clobbering them.

### `scripts/control-plane/run.sh`

```bash
#!/bin/bash
# Install (or re-install) the k3s control plane.
#
# All configuration goes to /etc/rancher/k3s/config.yaml rather than
# INSTALL_K3S_EXEC. CLI flags in the systemd unit override config-file lists
# entirely, so anything left on the command line here cannot be changed later
# without another reinstall -- which is what made the IP-change cron so
# destructive. See docs/plans/03-k3s-config-migration.md.
set -euo pipefail

EXTRA_SAN="${1:-$(hostname)}"
IP="$(hostname --all-ip-addresses | awk '{print $1}')"

# Never let a re-run silently change the k3s version. On an existing node we pin
# to what is already installed; upgrades are the job of system-upgrade-controller
# (see plan 05). K3S_VERSION overrides for a deliberate fresh install.
if command -v k3s >/dev/null 2>&1; then
    INSTALL_K3S_VERSION="$(k3s --version | awk '/^k3s version/ {print $3}')"
else
    INSTALL_K3S_VERSION="${K3S_VERSION:?set K3S_VERSION for a first install, e.g. v1.36.4+k3s1}"
fi
export INSTALL_K3S_VERSION

sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml >/dev/null <<EOF
write-kubeconfig-mode: "0644"
node-taint:
  - "node-role.kubernetes.io/control-plane=true:NoSchedule"
advertise-address: "${IP}"
tls-san:
  - "${EXTRA_SAN}"
  - "${IP}"
# k3s ships local-path as a StorageClass annotated is-default-class=true from its
# bundled manifest, and Longhorn marks its class default too -- two defaults, and
# Kubernetes picked between them arbitrarily. A kubectl patch does not hold: the
# addon controller re-applies on upgrade. Every PVC here uses Longhorn, and
# local-path cannot expand and pins data to one node. See STATE.md session 5.
disable:
  - local-storage
EOF

# The public IP lives in a drop-in that ip.sh rewrites; seed it if absent.
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
```

### `scripts/control-plane/ip.sh`

```bash
#!/bin/bash
# Hourly from cron. When the ISP lease changes, refresh the public IP in the k3s
# config and re-issue the API server certificate. Deliberately does NOT re-run
# the installer: that used to silently upgrade k3s, undrained, at whatever hour
# the lease happened to change.
set -euo pipefail

LOG_DIR="/home/gabeduke/log"
IPS_LOG="${LOG_DIR}/ips.log"
DROPIN="/etc/rancher/k3s/config.yaml.d/10-external-ip.yaml"

mkdir -p "${LOG_DIR}"
touch "${IPS_LOG}"

CURRENT_IPV4="$(dig +short myip.opendns.com @resolver1.opendns.com)"
LAST_IPV4="$(tail -1 "${IPS_LOG}" | awk -F, '{print $2}')"

# A failed lookup must not be mistaken for a new address.
if ! printf '%s' "$CURRENT_IPV4" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    echo "$(date): could not resolve public IP (got '${CURRENT_IPV4}') -- skipping"
    exit 0
fi

if [ "$CURRENT_IPV4" = "$LAST_IPV4" ]; then
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

# Force regeneration of the serving cert: k3s caches the SAN set in both of these.
sudo k3s kubectl -n kube-system delete secret k3s-serving --ignore-not-found
sudo rm -f /var/lib/rancher/k3s/server/tls/dynamic-cert.json
sudo systemctl restart k3s

echo "$(date): k3s restarted; new SANs:"
sleep 20
echo | openssl s_client -connect 127.0.0.1:6443 2>/dev/null \
  | openssl x509 -noout -text | grep -A2 'Subject Alternative Name' || true
```

### `scripts/agent/run.sh`

Same version-pinning treatment (S6-8): an agent re-run must not change the k3s
version either. Note the agents' `--node-external-ip` is **never refreshed** —
all three nodes currently advertise `96.228.35.135`, and only the control plane
has the cron. Either give agents the same drop-in mechanism, or accept it and
document it; for a single-homed home network it has not mattered.

---

## Execution

Do this **at a keyboard, not from cron**, with a rollback ready.

```bash
# 0. Back up everything the change touches.
ssh gabeduke@alphapi 'sudo cp /etc/systemd/system/k3s.service ~/k3s.service.bak-$(date +%F) && \
  sudo cp -r /etc/rancher/k3s ~/rancher-k3s.bak-$(date +%F) && \
  sudo cp /var/lib/rancher/k3s/server/tls/dynamic-cert.json ~/dynamic-cert.json.bak-$(date +%F) 2>/dev/null; \
  crontab -l > ~/crontab.bak-$(date +%F)'

# 1. Record the current state to compare against afterwards.
kubectl get nodes -o wide > /tmp/pre-nodes.txt
kubectl get cert -A > /tmp/pre-certs.txt
kubectl get applications -n argocd > /tmp/pre-apps.txt
ssh gabeduke@alphapi 'sudo cat /etc/systemd/system/k3s.service' | grep -A20 ExecStart

# 2. Disable the cron BEFORE changing anything, so it cannot fire mid-migration.
ssh gabeduke@alphapi "crontab -l | grep -v 'ip.sh' | crontab -"

# 3. Push and run the new scripts.
make sync
ssh gabeduke@alphapi 'sh run.sh alphapi'

# 4. Verify (below), then re-enable cron.
make setup-cron
```

### Verification

```bash
# The unit should now carry no configuration beyond `server`.
ssh gabeduke@alphapi 'grep -A5 ExecStart /etc/systemd/system/k3s.service'

# The SAN list must contain alphapi, the LAN IP, and the public IP.
ssh gabeduke@alphapi "echo | openssl s_client -connect 127.0.0.1:6443 2>/dev/null \
  | openssl x509 -noout -text | grep -A3 'Subject Alternative Name'"

# The session-5 storage fix must have survived the migration.
kubectl get sc                          # longhorn default, NO local-path
kubectl get addon -A 2>/dev/null | grep local-storage   # must be absent

# Nothing else moved.
kubectl get nodes -o wide | diff /tmp/pre-nodes.txt -
kubectl get cert -A      | diff /tmp/pre-certs.txt -
kubectl get applications -n argocd | diff /tmp/pre-apps.txt -
kubectl get node alphapi -o jsonpath='{.spec.taints}'   # control-plane taint intact
```

Then dry-run the cron path without waiting for a real lease change:

```bash
ssh gabeduke@alphapi 'sudo sed -i "$ s/.*/$(date +%F),1.2.3.4/" ~/log/ips.log'  # fake a stale last-IP
ssh gabeduke@alphapi 'bash ip.sh'      # should rewrite the drop-in and restart k3s once
kubectl get nodes                      # back to Ready
```

### Rollback

```bash
ssh gabeduke@alphapi 'sudo cp ~/k3s.service.bak-<date> /etc/systemd/system/k3s.service && \
  sudo rm -rf /etc/rancher/k3s && sudo cp -r ~/rancher-k3s.bak-<date> /etc/rancher/k3s && \
  sudo systemctl daemon-reload && sudo systemctl restart k3s'
```

The old unit hardcodes the full flag set, so restoring it restores the previous
behaviour exactly — including `--disable local-storage`.

---

## Commit

```
Stop the IP-change cron from reinstalling k3s

ip.sh called run.sh with no arguments on every ISP lease change. run.sh had
set -x but no set -eu, so ${1} expanded empty: the API server certificate was
re-issued without the `alphapi` SAN, and `curl | sh` reinstalled whatever
k3s stable resolved to at that moment -- undrained, unreviewed, hourly-triggered.

Move all k3s configuration from the systemd unit into /etc/rancher/k3s/config.yaml
(CLI flags override config-file lists entirely, so the unit had to be emptied for
the config file to have any effect), and have ip.sh rewrite only a drop-in and
re-issue the serving certificate instead of re-running the installer.

run.sh now pins INSTALL_K3S_VERSION to the installed version, so a re-run can
never change the k3s version; upgrades belong to system-upgrade-controller.
```
