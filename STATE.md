# Homelab — session state

**Last updated:** 2026-09-08 (session 7) · **Branch:** `main` · **Cluster:** `alphapi`, k3s v1.35.5+k3s1

---

## Read this first

1. **The tree is clean and `main` is 4 commits ahead of `origin/main`.**
   Plans 01 and 02 are merged. Nothing is pushed — decide whether to push
   before starting new work.
2. **Six implementation plans live in `docs/plans/`.** They are self-contained —
   context, exact diffs, verification, rollback. Do not re-derive them.
   `docs/plans/README.md` has the dependency order.
3. **Plans 01 and 02 are DONE.** Everything left (03–06) is **high risk** and
   touches live cluster or node state. There is no cheap one remaining.
4. **SSH to nodes depends on the login keyring being unlocked.** `ssh-add -l`
   still reports "The agent has no identities", but `ssh gabeduke@alphapi true`
   succeeds — the on-disk key is being used directly, so an empty agent is
   **not** by itself a blocker. Test the real thing, not `ssh-add -l`.

---

## Branch state

`main`, working tree clean, **4 commits ahead of `origin/main` (unpushed)**:

```
23223ca  Update STATE.md and plans README for session 7
0ee2d6e  Fix four Makefile bugs: remote patching, kubeconfig merge/fetch, node lists
0a2bf31  Fix false-success NFS module loading; de-duplicate and gate setup scripts
a7c0eb1  Add session-6 provisioning review plans and update STATE.md
```

Merged fast-forward from `provisioning-review-plans-01-02` (branch deleted).
`origin/main` is still at `9a7df68`.

## Active work — the six plans

| Plan | Covers | Risk | Status |
|---|---|---|---|
| `01-makefile-and-docs` | `make patch` broken, kubeconfig targets, node lists, stale taint doc | low | **DONE, verified** |
| `02-nfs-and-setup-scripts` | sudo modprobe, dedupe, dead file, reboot gate | low | **DONE, verified** |
| `03-k3s-config-migration` | IP cron silently reinstalls k3s | **high** | **next** |
| `04-cert-manager-upgrade` | 1.14.5 → 1.21.x | **high** | pending — **gates 05** |
| `05-k3s-136-upgrade` | wire up system-upgrade-controller, 1.35→1.36 | **high** | pending |
| `06-ubuntu-lts-upgrade` | both workers on an EOL Ubuntu | **high** | pending |

**Order matters in one place:** 04 must precede 05. cert-manager 1.14 supports
Kubernetes up to ~1.29 and **1.21 is the only release supporting 1.36**.

---

## The three findings most likely to be lost

Everything else is written down in the plans. These three are the ones a fresh
session would otherwise re-derive the hard way.

**1. cert-manager is the gating dependency, not a footnote.**
Deployed 1.14.5 went **EOL October 2024** and is already six minors past its
Kubernetes ceiling on the current 1.35 cluster. Verified against the real
`values.schema.json` in `cert-manager-v1.21.1.tgz`: the existing Helm values
survive the jump unchanged — `installCRDs` still validates (deprecated →
`crds.enabled`/`crds.keep`), `prometheus.enabled` still exists, and none of the
keys removed in 1.21 are set. None of 1.21's three breaking changes apply here.

**2. k3s CLI flags override config-file lists entirely.**
From the k3s docs: for repeatable args like `tls-san`, *"the CLI arguments will
overwrite all values in the list."* So a `/etc/rancher/k3s/config.yaml` is
**ignored** while `--tls-san=` remains in the systemd unit `ExecStart`. Writing
the config file and restarting would appear to work and change nothing. This is
why plan 03 is a structural migration rather than a one-line fix.

**3. `set -o pipefail` + `grep -q` is a live trap on these nodes.**
`lsmod | grep -q ...` — `grep -q` exits at first match, `lsmod` takes SIGPIPE,
pipefail turns that into **exit 141**, so the branch silently doesn't fire.
Reproduced on alphapi (134 modules), not on betapi (148) — it is timing, not
size, so it is non-deterministic. Workstation stub tests passed the buggy code;
only running it on the nodes caught it. Snapshot command output into a variable
and match with `case` instead.

---

## What plan 02 actually found (corrections worth keeping)

The finding that drove plan 02 (S6-5: `modprobe` called without `sudo`, with
fallback logic that reports success anyway) was **real as a code bug but had no
practical impact**:

- All four modules (`sunrpc lockd nfs nfsd`) were already loaded on all three
  nodes, none builtin, and `/etc/modules-load.d/k3s-nfs.conf` already listed them.
- Why it worked anyway: the old script's *persistence* path used `modprobe -n` —
  a **dry run that succeeds unprivileged** — so the file was written correctly
  even though the load path failed. `systemd-modules-load.service` then did the
  real loading at boot. The broken half never mattered.
- The "Operation not permitted" failure was **never reproduced** on these nodes;
  with every module already loaded, `modprobe` is a no-op success regardless of
  privileges. The `sudo` fix is right by construction (loading needs
  `CAP_SYS_MODULE`) but the original finding overstated what was observed. It
  would matter on a **fresh** node — where `make setup` runs first.

Also incidental, and **not a problem**: `/proc/cmdline` on the workers contains
`cgroup_disable=memory`, which `setup.sh` is meant to strip. It comes from the Pi
**firmware's prepended cmdline**, not `cmdline.txt`, so the script cannot and need
not remove it — the later `cgroup_enable=memory` wins and `memory` is present in
`/sys/fs/cgroup/cgroup.controllers`. That code path will simply never fire.

---

## What plan 01 actually found

- **`make patch` had never patched anything.** Make runs each recipe line through
  a *local* `/bin/sh`, so in `ssh $(NODE) sudo apt-get update && sudo apt-get
  upgrade -y` the `&&` was parsed locally: `update` ran on the Pi, `upgrade -y`
  ran on the Mac. Demonstrated directly — under the old shape the second command
  reported hostname `dukemon`, under the quoted shape both report `betapi`.
  The backlog cost is real: **alphapi has 111 pending package upgrades**,
  betapi and charliepi 38 each. Relevant to plan 06.
- **`make merge-kubeconfig` had never merged.** Verified with a probe kubeconfig
  carrying a context name absent from `~/.kube/config`: the old lowercase
  `kubeconfig=` form produced **0** references to it, the fixed `KUBECONFIG=`
  form produced 5. It was harmless only because the flattened dump it wrote back
  happened to be `~/.kube/config` itself.
- **`make get-kubeconfig` produced an unusable file** — `chown gabeduke:gabeduke`
  fails on macOS (the group is `staff`) and the fetched file pointed at
  `127.0.0.1`. Now chmod 600 + server rewritten to `$(CONTROL_IP)`;
  `KUBECONFIG=.k3s.yaml kubectl get nodes` succeeds from the Mac.
- **`.k3s.yaml` was not gitignored.** It holds cluster-admin credentials and was
  untracked-but-not-ignored, so any `git add -A` would have staged it. Added.

---

## Cluster facts

```
alphapi     control-plane   v1.35.5+k3s1   Ubuntu 22.04.2 LTS   5.15.0-1105-raspi
betapi      worker          v1.35.5+k3s1   Ubuntu 25.10 (EOL)   6.17.0-1003-raspi
charliepi   worker          v1.35.5+k3s1   Ubuntu 25.10 (EOL)   6.17.0-1003-raspi
```

k3s stable channel: **v1.36.4+k3s1**. Longhorn **v1.10.1**. cert-manager **1.14.5**.
`mothership` / `bigpi` appear in the Makefile but are **not in the cluster**.

Healthy baseline: 5 ArgoCD apps Synced/Healthy · certs **15/15 True** ·
Longhorn 7 attached / 2 detached · `longhorn` is the **sole** default StorageClass.
The one expected non-Running pod is `plant-shop-0` (`ContainerCreating`, ~10d) —
pre-existing ext4 corruption, see backlog.

### Gotchas that have already caused outages

- **Taint key.** Live taint is `node-role.kubernetes.io/control-plane`. The
  deprecated `master` key caused the session-1 off-network outage (`svclb-traefik`
  tolerates `control-plane`, so it never scheduled). `CLAUDE.md` documented
  `master` until plan 01; **fixed** in `0ee2d6e`.
- **Two default StorageClasses.** Fixed in session 5 via `--disable local-storage`
  at the k3s level. A `kubectl patch` does **not** hold: `local-path` is owned by
  the k3s addon controller from a bundled manifest that is re-applied on upgrade,
  and `longhorn`'s class is owned by longhorn-manager from a ConfigMap.
  **Re-verify this survived after any k3s upgrade** (`kubectl get sc`).
- **ArgoCD Helm values are not schema-checked before apply.** A bare
  `persistence.enabled: true` in the k8s-at-home common chart (where `persistence`
  is a *map of named volumes*) broke mosquitto rendering for a **year** —
  `selfHeal` could not recreate the PVC because the app could not render at all.
  Render locally before applying: `helm template ... -f values.yaml`.
- **A makefile variable can hijack the recipe environment.** `Makefile` defined
  `KUBECONFIG = $(shell ssh ... cat k3s.yaml)`. If a variable of that name is
  present in make's environment at startup, make re-exports **its** value into
  every recipe — so `KUBECONFIG=... make diff` would have pointed every kubectl
  call in the file at the literal text of `k3s.yaml`. It was never referenced,
  and is deleted in `0ee2d6e`. Do not reintroduce a makefile variable whose name
  collides with a tool's environment variable.
- **`make iot` has a review gate** (`make diff` → `make approve` → apply) added
  after a blind apply would have silently upgraded ArgoCD and dropped 11 people
  from the forward-auth whitelist. `make apply-iot` bypasses it. Do not use
  `make -j` with it.

---

## Backlog (not yet planned)

1. **plant-shop ext4 corruption** — `Resize inode not valid`, `RUN fsck MANUALLY`.
   Needs manual `fsck` on `/dev/longhorn/pvc-dd559b8a-...` from a maintenance pod.
   Data risk — back up first.
2. **Longhorn disk imbalance** — betapi 125GB / charliepi 62GB / alphapi 31GB with
   `default-replica-count: 2` and strict anti-affinity. Already broke the
   Prometheus volume expansion once; will do it again. **Also constrains plan 05**
   (agent Plan concurrency must be 1, not 2).
3. **Repoint the three MQTT clients** off the public-IP hairpin
   (`mqtt.leetserve.com` → public IP → hairpin). Target
   `mosquitto.mosquitto.svc.cluster.local:1883`:
   | Client | Set where | Cost |
   |---|---|---|
   | `reap` | `BROKER` env, `~/repos/reap/deploy/reap.yaml:24` | cheap, manifest edit |
   | `event-checker` | **hardcoded** `app/config.py:11` | code + image rebuild |
   | `room-checker` | **hardcoded** `app/config.py:8` | code + image rebuild |
   `eventchk` also runs a date window that expired Nov 2024 — it connects but
   likely does nothing useful.
4. **Bring 4 out-of-repo ingresses into the repo** — `eventchk`, `roomchk`,
   `travel-happy`, `fretbook-dev`; fixed live only, in session 3.
5. **Cleanup** — delete `default/rwx-debug-1765122160` (leftover debug pod).
6. **Longhorn 1.10.1 is near end of support** (upstream is 1.12.x). Queue an
   upgrade as separate work; not a blocker for plan 05.
7. `patch-manager-tolerations.yaml:10` / `patch-ui-tolerations.yaml:10` still name
   the deprecated `master` key. Harmless — both also list `control-plane` on line 13.

---

## History

**Session 7 (this one)** — Committed plan 02 (verified in session 6) and the six
plan documents, then implemented and verified plan 01. Merged to `main`
(fast-forward, 4 commits, **unpushed**). No cluster or node state was changed:
every verification was read-only or repo-local. `make patch` was deliberately
**not** run — see plan 06.

**Session 6** — Reviewed `scripts/` + `Makefile`. Found 13 issues
(`S6-1`…`S6-13`), researched each, wrote six plans, implemented and verified
plan 02. No cluster or node state changed beyond re-running idempotent setup.

**Session 5** — Removed the duplicate default StorageClass; `longhorn` is now sole
default. See *Gotchas* above for why a `kubectl patch` would not have held.

**Session 4** — Fixed mosquitto (`b6a982c`), unsyncable since 2024-08-06 from a
one-line values bug. Three dependent clients (`reap`, `eventchk`, `roomchk`)
recovered on their own within ~4 min, no changes to their repos. Also found the
`config: mosquitto.conf:` block had been **silently ignored for 9 months** —
chart 4.4.0 has no top-level `config` value, it generates `mosquitto.conf` itself.
Removed. To actually set retention options, override
`persistence."mosquitto-config"` as a `type: custom` ConfigMap mount.
The original mosquitto data was **not recoverable** — no orphaned PV survived.

**Sessions 1–3** — Off-network access restored (taint key mismatch, above).
Certificates 10-failing → 15/15 green, all ingresses on `letsencrypt-aws-prod`
(DNS01). Prometheus recovered from a 2772-restart crashloop (`retentionSize: 5GiB`
on a `5Gi` volume left no WAL/compaction headroom; now `6GiB` on `10Gi`).
`make iot` review gate added. ArgoCD pinned to v3.2.1 (had tracked floating
`stable`). Incident writeup: `docs/tls-http01-outage.md`.

**Standing priorities:** control plane first (DNS, ingress, off-network access to
prototypes behind ingress auth); monitoring second; stateful/Longhorn last.

---

## Handy commands

```bash
# health sweep
kubectl get nodes -o wide
kubectl get applications -n argocd
kubectl get cert -A
kubectl -n longhorn-system get volumes.longhorn.io
kubectl get sc                                    # longhorn must be sole default
kubectl -n kube-system get ds | grep svclb        # expect DESIRED 3

# render an ArgoCD Helm Application locally BEFORE applying --
# this is what would have caught the mosquitto bug a year earlier
helm template mosquitto ./mosquitto --namespace mosquitto -f values.yaml

# per-node port reality check (use the exit code, not just http_code)
for ip in 192.168.1.84 192.168.1.26 192.168.1.234; do
  printf "%-15s :443 -> " "$ip"
  curl -sk --max-time 5 -o /dev/null -w 'http=%{http_code}' "https://$ip/"; echo " exit=$?"
done

# node access (keyring must be unlocked)
ssh gabeduke@alphapi true && echo "ssh ok"
make check-nfs-modules
```
