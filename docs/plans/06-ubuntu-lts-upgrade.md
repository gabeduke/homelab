# Plan 06 — Get the nodes onto a supported Ubuntu

**Finding:** S6-3 · **Risk: HIGH** on alphapi, medium on the workers
**Cluster impact:** one node down per upgrade · **Needs SSH:** yes
**Blocked by:** plan 01 (`make patch` is broken), ideally plan 05

---

## Current state

```
alphapi     Ubuntu 22.04.2 LTS   5.15.0-1105-raspi   control-plane, 2y+ old
betapi      Ubuntu 25.10         6.17.0-1003-raspi
charliepi   Ubuntu 25.10         6.17.0-1003-raspi
```

**Both workers are on an unsupported release.** Ubuntu 25.10 is an interim
release with nine months of support; it reached end of life on **9 July 2026**.
They have been receiving no security updates for two months.

`alphapi` is on 22.04 LTS, supported until April 2027, but is now three kernel
generations behind the workers and shows `Ubuntu 22.04.2` — a point release from
early 2023, which suggests it has not taken updates in a long time.

That is explained by **S6-2 (plan 01)**: `make patch` sends `apt-get update` to
the node and runs `apt-get upgrade` on the Mac. No node has ever been upgraded by
it. **Fix plan 01 first**, then run a real `make patch` on every node — that
alone may bring `alphapi` from 22.04.2 to 22.04.x current, and is a prerequisite
for any release upgrade.

---

## Sequencing

Two independent decisions: **which order**, and **upgrade vs. rebuild**.

### Order

1. **`make patch` everywhere first** (needs plan 01). A release upgrade from a
   stale package set is asking for trouble.
2. **Workers before the control plane**, one at a time. They are the ones
   actually out of support, and a worker is recoverable — cordon, drain, and the
   cluster keeps running.
3. **`alphapi` last, and only after both workers are proven.** It holds the k3s
   datastore and is a single point of failure.

### Do this after plan 05, not before

k3s v1.36 on the current kernels is a known-good combination — that is what the
upgrade will be tested against. Changing the OS *and* Kubernetes at once means a
failure has two candidate causes. Get to a supported Kubernetes first, then move
the OS underneath it.

If you would rather do the OS first because the EOL exposure bothers you more,
that is defensible — just do not do both in one sitting.

---

## Workers: 25.10 → 26.04 LTS

Direct upgrade from 25.10 to 26.04 is supported.

```bash
NODE=betapi     # one at a time

# 1. Drain. Longhorn needs the replica elsewhere before the node goes down.
kubectl -n longhorn-system get volumes.longhorn.io   # all healthy first
kubectl cordon $NODE
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=10m

# 2. Fully patch on the current release.
ssh gabeduke@$NODE 'sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y'
ssh gabeduke@$NODE 'sudo reboot'      # take the kernel it just installed

# 3. Release upgrade. Interactive -- run it in tmux so a dropped SSH does not
#    kill it mid-transaction.
ssh gabeduke@$NODE
  grep Prompt /etc/update-manager/release-upgrades   # must be Prompt=normal for 25.10 -> 26.04
  sudo apt-get install -y update-manager-core
  tmux new -s upgrade
  sudo do-release-upgrade
```

`do-release-upgrade` asks about modified config files. **Keep the local version**
for anything under `/etc/rancher/`, `/etc/systemd/system/k3s*`, and
`/etc/modules-load.d/k3s-nfs.conf`. Read each prompt; do not accept the
maintainer's version by reflex.

```bash
# 4. Back in the cluster.
ssh gabeduke@$NODE 'lsb_release -a && uname -r'
ssh gabeduke@$NODE 'systemctl status k3s-agent --no-pager'
ssh gabeduke@$NODE 'lsmod | grep -E "^(nfs|lockd|sunrpc)"'   # NFS modules survived?
kubectl get nodes                                            # $NODE Ready
kubectl uncordon $NODE
kubectl -n longhorn-system get volumes.longhorn.io           # rebuild to healthy
```

**Wait for Longhorn to finish rebuilding replicas before touching the second
worker.** This can take a while on a Pi; `kubectl -n longhorn-system get
replicas.longhorn.io` shows progress.

### Raspberry Pi specifics to watch

- The kernel is the `linux-raspi` flavour, not generic. Confirm
  `apt-cache policy linux-raspi` resolves on 26.04 **before** starting.
- `/boot/firmware` is a small FAT partition; a release upgrade installing several
  kernels can fill it. Check `df -h /boot/firmware` first and
  `sudo apt-get autoremove --purge` old kernels if it is tight.
- The cgroup parameters `setup.sh` appends to `cmdline.txt` live on that
  partition. Verify they survived: `cat /proc/cmdline | grep cgroup_memory`.
  If they are gone, k3s will not start — re-run `make setup` (with plan 02's
  `REBOOT=1` gate).
- Serial console access is the only recovery if the Pi does not come back.
  **Have physical access before starting**, or be willing to reflash.

---

## alphapi: 22.04 → 24.04 → 26.04

There is no direct 22.04 → 26.04 path. LTS upgrades go one LTS at a time, so this
is **two** `do-release-upgrade` runs with a healthy interval between them.

This is the highest-risk operation in any of these plans: a two-hop release
upgrade on a 2+ year old install that holds the k3s datastore and is the
cluster's only control plane.

```bash
# Back up the datastore and all k3s config BEFORE anything.
ssh gabeduke@alphapi 'sudo cp -r /var/lib/rancher/k3s/server/db ~/k3s-db.bak-$(date +%F) && \
  sudo cp -r /etc/rancher/k3s ~/rancher-k3s.bak-$(date +%F) && \
  sudo cp /etc/systemd/system/k3s.service ~/k3s.service.bak-$(date +%F) && \
  crontab -l > ~/crontab.bak-$(date +%F)'

# Pull the backup off the node -- a failed upgrade may take the filesystem with it.
scp -r gabeduke@alphapi:~/k3s-db.bak-* ./alphapi-backup/
```

Then per hop: `sudo do-release-upgrade` → reboot → confirm k3s server healthy,
all nodes Ready, certificates green, ArgoCD apps Synced → only then the next hop.

### Seriously consider rebuilding instead

For `alphapi` specifically, a clean 26.04 install plus a restore may be both
safer and faster than two release upgrades on a 2-year-old system:

| | Two-hop upgrade | Rebuild |
|---|---|---|
| Config drift from 2+ years | carried forward, including whatever is undocumented | eliminated |
| Failure mode | half-upgraded control plane, serial console recovery | reflash and retry, cluster still has the old SD card |
| Provisioning scripts | not exercised | **exercised end to end** — proves `run.sh` actually works |
| Time | two long unattended runs | one flash + `make apply-cluster` |

The rebuild path only becomes attractive **after plan 03**, which moves k3s
configuration into `config.yaml` and makes `run.sh` a faithful description of the
node. Today the live systemd unit has hand-edits (session 5's
`--disable local-storage`) that a rebuild would need to reproduce by hand.

A rebuild also needs the k3s datastore restored, or the cluster rebuilt from the
repo. Given every workload here is GitOps-managed through ArgoCD, "rebuild the
control plane and re-apply from git" is a real option — and would be a genuinely
useful thing to have proven at least once.

**Decide this before starting.** It is not a decision to make halfway through a
`do-release-upgrade`.

---

## Verification (all nodes, after each)

```bash
ssh gabeduke@$NODE 'lsb_release -d && uname -r && cat /proc/cmdline | tr " " "\n" | grep cgroup'
kubectl get nodes -o wide
kubectl get pods -A | grep -vE 'Running|Completed'
kubectl -n longhorn-system get volumes.longhorn.io
kubectl get cert -A
kubectl get applications -n argocd
make check-nfs-modules
```

---

## Commit

Mostly an operational task; the repo change is small — record the target release
so the provisioning scripts and `CLAUDE.md` stop implying 22.04:

```
Document Ubuntu 26.04 LTS as the node baseline

Both workers were on 25.10, which reached EOL on 2026-07-09; alphapi was on a
22.04 point release from early 2023. `make patch` had never actually upgraded
any node (see plan 01), which is why they drifted this far apart.
```
