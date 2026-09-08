# Plan 05 — Wire up system-upgrade-controller, then k3s 1.35.5 → 1.36.4

**Finding:** S6-4 · **Risk: HIGH** — rolling node upgrade with storage attached
**Cluster impact:** every node cordoned, drained, and restarted, one at a time
**Needs SSH:** not for the upgrade itself; yes for recovery
**Blocked by: plan 04** (cert-manager must be on 1.21 before Kubernetes 1.36)

---

## Current state

```
alphapi    v1.35.5+k3s1   control-plane
betapi     v1.35.5+k3s1
charliepi  v1.35.5+k3s1
```

Stable channel resolves to **v1.36.4+k3s1**.

`clusters/iot/namespace-system-upgrade/` contains correct, well-commented Plans
for exactly this — and none of it has ever run:

- **Not applied.** `namespace-system-upgrade` is absent from the `resources:` list
  in `clusters/iot/kustomization.yaml`.
- **Not installed.** `kubectl get all -n system-upgrade` → no resources;
  `kubectl get plans -A` → `the server doesn't have a resource type "plans"`.
- **Would match nothing.** Both Plans select on `{key: k3s-upgrade, operator: Exists}`.
  No node carries that label. Applying it as-is would install a controller that
  upgrades zero nodes — which, conveniently, is exactly the safe first step.
- **Unpinned twice.** The kustomization fetches `releases/latest/download/...`,
  and both Plans use `channel: .../stable`. Either can change what gets deployed
  without a repo change.

So the cluster has been reaching new k3s versions by some other route — almost
certainly the IP-change cron in **plan 03**. Doing plan 03 first removes that
accidental upgrade path; this plan replaces it with a deliberate one.

---

## A correctness bug in the existing manifest

```yaml
resources:
- https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml
- k3s.yaml
```

In current releases, `system-upgrade-controller.yaml` **no longer contains the
CRD** — it was split into a separate `crd.yaml`. Verified against v0.20.1:

```
$ grep -c CustomResourceDefinition system-upgrade-controller.yaml
0
$ grep '^kind:' crd.yaml
kind: CustomResourceDefinition      # plans.upgrade.cattle.io
```

The [k3s docs](https://docs.k3s.io/upgrades/automated) install both:
`kubectl apply -f crd.yaml -f system-upgrade-controller.yaml`.

As written, applying this kustomization installs the controller and then fails on
`kind: Plan` — no matching resource type. **Both files are required.**

---

## Changes

### `clusters/iot/namespace-system-upgrade/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: system-upgrade

resources:
# Pinned deliberately. `latest` here means a `make iot` can silently change the
# component that upgrades every node in the cluster.
# CRD and controller are separate files in current releases -- the controller
# manifest alone does not define `kind: Plan`.
- https://github.com/rancher/system-upgrade-controller/releases/download/v0.20.1/crd.yaml
- https://github.com/rancher/system-upgrade-controller/releases/download/v0.20.1/system-upgrade-controller.yaml
- k3s.yaml
```

The controller manifest creates the `system-upgrade` Namespace itself, so no
addition to `make namespaces` is needed.

### `clusters/iot/namespace-system-upgrade/k3s.yaml`

Replace the channel with an explicit version in **both** Plans:

```yaml
  # Pinned, not `channel: .../stable`. A channel makes every node upgrade the
  # moment upstream promotes a release -- unattended, and with no repo change to
  # review. Bump this line deliberately.
  version: v1.36.4+k3s1
```

The `+` is handled: the controller converts it to `-` for the image tag.
Confirmed that `rancher/k3s-upgrade:v1.36.4-k3s1` exists and publishes
**arm64** (as well as amd64 and arm) — required for the Pis.

Leave everything else. The Plans are already right: `concurrency: 1` for servers,
`cordon: true`, agents gated behind a `prepare` container that waits on
`k3s-server`, and `drain.force: true` with `skipWaitForDeleteTimeout: 60`.

### `clusters/iot/kustomization.yaml`

```yaml
resources:
- namespace-argocd
- namespace-cert-manager
- namespace-kube-system
- namespace-longhorn-system
- namespace-minecraft
- namespace-monitoring
- namespace-system-upgrade      # add
```

> **CRD/CR ordering.** `kubectl apply -k` sorts CRDs ahead of custom resources,
> but does not wait for the CRD to become *established*. The first apply may fail
> with `no matches for kind "Plan"`. That is benign — re-run `make apply-iot` and
> it succeeds. Alternatively apply the CRD by itself once, first.

---

## Pre-flight

### Kubernetes 1.36 deprecations — checked against this cluster

| Change in 1.36 | This cluster |
|---|---|
| `gitRepo` volumes permanently disabled | **none** — no pod uses one |
| Service `externalIPs` deprecated | **none** — no Service sets it |
| kube-proxy IPVS mode deprecated | n/a — k3s defaults to iptables, no override |
| SELinux volume relabel default change | n/a — Ubuntu uses AppArmor |

```bash
# Re-run these before starting; they were clean at review time.
kubectl get pods -A -o json | grep -c gitRepo                     # 0
kubectl get svc -A -o json | grep -c '"externalIPs"'              # 0
```

### Components

- **cert-manager** — must already be 1.21.x. **This is plan 04 and it is a hard
  gate.** `kubectl -n cert-manager get deploy cert-manager -o jsonpath='{..image}'`
- **Longhorn 1.10.1** — no upper Kubernetes bound published; Longhorn supports
  versions at or above its minimum. Current upstream is 1.12.x, so 1.10 is near
  the end of its support window. Not a blocker for this plan, but queue a
  Longhorn upgrade as separate work.
- **Traefik / svclb** — bundled with k3s, upgraded in lockstep. Watch that the
  control-plane toleration still holds after the upgrade (session 1's outage).

### Storage — the real risk in a rolling node upgrade

Each node gets drained. Longhorn must keep a healthy replica elsewhere for every
volume throughout.

```bash
kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=\
NAME:.metadata.name,STATE:.status.state,ROBUST:.status.robustness,REPLICAS:.spec.numberOfReplicas
```

**Every volume must be `attached`/`healthy` before starting.** Note from `STATE.md`:

- `default-replica-count: 2` with strict anti-affinity across 3 nodes — draining
  one node is fine; two at once is not. The agent Plan has `concurrency: 2` and
  there are exactly **two** agents, so **both workers would drain together.**
  **Set `concurrency: 1` on the agent Plan** for this cluster, or a two-replica
  volume can lose both replicas at once.
- Disk imbalance (betapi 125GB / charliepi 62GB / alphapi 31GB) already broke a
  Prometheus expansion once.
- The `plant-shop` volume has known ext4 corruption (carried-over next step #1).
  Consider resolving or detaching it before draining its node.

### Backups

```bash
ssh gabeduke@alphapi 'sudo cp -r /var/lib/rancher/k3s/server/db ~/k3s-db.bak-$(date +%F) && \
  sudo cp -r /etc/rancher/k3s ~/rancher-k3s.bak-$(date +%F)'
kubectl get nodes -o wide > /tmp/pre-upgrade-nodes.txt
kubectl get cert -A        > /tmp/pre-upgrade-certs.txt
kubectl get applications -n argocd > /tmp/pre-upgrade-apps.txt
kubectl get pods -A        > /tmp/pre-upgrade-pods.txt
```

---

## Execution — one node at a time

The node label is the throttle. Nothing upgrades until a node is labelled.

```bash
# 1. Install the controller. Upgrades nothing: no node carries the label yet.
make diff
make iot                              # re-run if it reports: no matches for kind "Plan"

kubectl -n system-upgrade get pods    # controller Running
kubectl get plans -A                  # both Plans present, 0 applied

# 2. Control plane FIRST. Servers must precede agents.
kubectl label node alphapi k3s-upgrade=true

kubectl -n system-upgrade get jobs -w
kubectl get nodes -w                  # alphapi: cordon -> SchedulingDisabled -> Ready v1.36.4+k3s1
```

The API server restarts here. `kubectl` will drop briefly — expected. With a
single control plane there is no HA; this is a short control-plane outage.
Workloads keep running.

```bash
# 3. Confirm the control plane is fully healthy before touching a worker.
kubectl get nodes -o wide
kubectl get pods -A | grep -vE 'Running|Completed'
kubectl -n longhorn-system get volumes.longhorn.io   # all healthy again
kubectl get cert -A | diff /tmp/pre-upgrade-certs.txt -
kubectl get sc                                        # longhorn still sole default

# 4. One worker.
kubectl label node betapi k3s-upgrade=true
kubectl -n system-upgrade get jobs -w
# wait for Ready + all Longhorn volumes healthy again, then:

# 5. The other worker.
kubectl label node charliepi k3s-upgrade=true
```

### After

```bash
kubectl get nodes -o wide                             # all v1.36.4+k3s1
kubectl get pods -A | diff /tmp/pre-upgrade-pods.txt - # only expected churn
kubectl get applications -n argocd                     # all Synced/Healthy
kubectl get node alphapi -o jsonpath='{.spec.taints}'  # control-plane taint intact
kubectl -n kube-system get pods | grep svclb           # 3 svclb-traefik pods (session 1)
```

Verify the session-5 storage fix survived — k3s upgrades re-apply bundled manifests,
which is precisely the scenario that made `--disable local-storage` necessary
rather than a `kubectl patch`:

```bash
kubectl get sc                                  # longhorn default; NO local-path
kubectl get addon -A | grep local-storage       # must be absent
ssh gabeduke@alphapi 'ls /var/lib/rancher/k3s/server/manifests/ | grep local-storage'  # absent
```

If `local-path` came back, the `disable` setting was lost in the upgrade —
re-check `/etc/rancher/k3s/config.yaml` (plan 03 moved it there).

### Leave the labels on, or take them off?

Taking them off after each upgrade means the next bump is again a deliberate,
one-node-at-a-time act. Leaving them on means editing `version:` in the repo
upgrades the whole cluster on the next `make iot`. **Recommendation: remove the
labels afterwards.** With one control plane and 2-replica storage, this cluster
does not want a hands-off rolling upgrade.

```bash
kubectl label node alphapi betapi charliepi k3s-upgrade-
```

### Rollback

k3s has no supported downgrade. Recovery is restore-from-backup:

```bash
ssh gabeduke@alphapi 'sudo systemctl stop k3s && \
  sudo rm -rf /var/lib/rancher/k3s/server/db && \
  sudo cp -r ~/k3s-db.bak-<date> /var/lib/rancher/k3s/server/db && \
  sudo systemctl start k3s'
```

This is why the upgrade goes one node at a time with a health check between each:
the cheap recovery is *stopping*, not reverting.

---

## Commit

```
Wire up system-upgrade-controller and pin k3s to v1.36.4+k3s1

The Plans have been in the repo since 2024 but never applied: the directory was
missing from clusters/iot/kustomization.yaml, and no node carried the k3s-upgrade
label the nodeSelector requires. Meanwhile the IP-change cron (plan 03) was
upgrading k3s by accident.

Also fixes the manifest itself: current releases split the Plan CRD into a
separate crd.yaml, so the kustomization as written would install the controller
and then fail on `kind: Plan`.

Pin the controller to v0.20.1 and replace `channel: stable` with an explicit
version in both Plans -- a channel upgrades every node whenever upstream
promotes a release, with no repo change to review.

Agent Plan concurrency 2 -> 1: there are exactly two agents, and Longhorn runs
two replicas with strict anti-affinity, so draining both at once can take out
both replicas of a volume.
```
