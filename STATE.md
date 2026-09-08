# Homelab — session state

**Last updated:** 2026-09-07 (session 5 — COMPLETE, pushed) · **Branch:** main · **Cluster:** `alphapi` (k3s v1.35.5)

---

## TL;DR — duplicate default StorageClasses fixed (session 5); mosquitto fixed (session 4)

`mosquitto` had been **unsyncable since 2025-09-21** because of a one-line values
bug that broke Helm rendering for the whole Application. Fixed, applied, and
verified: PVC recreated, broker `1/1 Running`, and the three dependent clients
recovered **on their own** with no changes to their repos.

**Session 5** removed the duplicate default StorageClass: `local-storage` is now
disabled at the k3s level, so `longhorn` is the **sole default**. Details below.

**Session 4** fixed mosquitto (`b6a982c`); `main` is in sync with `origin/main` and
the working tree is clean. That push went through cleanly — no secret-scanning block
and **no history rewrite**, unlike session 3.

**No open blockers.** Nothing was left half-done and no permission denials were hit
this session (session 3's `kubectl` classifier problems did not recur).

Sessions 1–3 (TLS outage, off-network access, Prometheus, `make iot` review gate)
are summarised under *Previously completed* below.

---

## The fix (session 5) — duplicate default StorageClasses

`local-path` **and** `longhorn` were both annotated `is-default-class: true`, so
Kubernetes chose arbitrarily for any PVC that omitted `storageClassName`. Long
suspected as the source of the recurring stateful nondeterminism.

**Why the plan recorded in session 4 would not have worked.** The obvious
`kubectl patch sc local-path ...` does not hold — neither class is free-standing:

| Class | Owned by | A kubectl patch would |
|---|---|---|
| `local-path` | k3s **Addon** `local-storage`, from the bundled `/var/lib/rancher/k3s/server/manifests/local-storage.yaml` (which hardcodes `is-default-class: "true"`) | survive restarts, then silently revert whenever a k3s upgrade ships a changed manifest — and this cluster auto-upgrades k3s |
| `longhorn` | `longhorn-manager`, from ConfigMap `longhorn-storageclass`, already patched by this repo (`patch-storageclass-configmap.yaml:12`) | be reverted by longhorn-manager |

**Which one loses was not close.** Every PVC in the cluster used longhorn
(7 `longhorn` + 2 `longhorn-retain`); **zero** used `local-path`. `local-path`
also cannot expand (`allowVolumeExpansion` unset) and is node-local, so anything
landing on it loses its data when the pod reschedules.

**What changed:** `--disable local-storage` added to k3s — in the systemd unit on
alphapi (backed up alongside as `k3s.service.bak-*`) and in
`scripts/control-plane/run.sh` so rebuilds keep it. k3s deleted the addon, the
StorageClass, the `local-path-provisioner` Deployment, and the bundled manifest.

**Verified:**
- `longhorn` is the **sole default**; `local-path` SC, provisioner Deployment,
  `local-storage` Addon and its manifest file are all gone.
- End-to-end: a PVC created with **no** `storageClassName` was assigned
  `longhorn` and bound in ~3s. Test PVC deleted; no orphaned PV.
- Across the k3s restart, nodes/taints, certificates (15/15) and all 5 ArgoCD apps
  are byte-identical to the pre-change snapshot. Running pods 74 → 73, exactly the
  removed `local-path-provisioner`. mosquitto still `1/1 Running`, 0 restarts.

**Reversible:** drop the flag from the unit + `run.sh` and restart k3s; k3s
re-deploys local-path from its bundled manifest.

---

## The fix (session 4)

**Root cause.** `clusters/iot/namespace-argocd/mosquitto.yaml` set a top-level
`persistence.enabled: true`. In the k8s-at-home common chart, `persistence` is a
**map of named volumes**, each with its own `enabled`. The template does
`range $index, $PVC := .Values.persistence`, so the bare bool blew up rendering:

```
_pvc.tpl:7:19: executing "common.pvc" at <$PVC.enabled>:
can't evaluate field enabled in type interface {}
```

Reproduced offline against chart 4.4.0 — byte-identical to the cluster's error.

**Causal chain, end to end:**

1. Broken render → ArgoCD `ComparisonError`. Last successful sync: **2024-08-06**.
2. So when PVC `mosquitto-data` went missing, `selfHeal` **could not recreate it** —
   the app could not render at all.
3. Pod `Pending` for 283 days (`persistentvolumeclaim "mosquitto-data" not found`).
4. Service had zero endpoints → `:1883` refused.
5. `reap`, `eventchk`, `roomchk` hard-fail on connect at import time → CrashLoopBackOff
   (2194–2234 restarts each).

**What changed in the repo** (one file, `mosquitto.yaml`):

| Change | Why |
|---|---|
| Removed top-level `persistence.enabled` | The actual bug. Now renders. |
| Added `storageClass: longhorn` to `persistence.data` | The cluster has **two default StorageClasses**; unset = arbitrary pick, and `local-path` would pin broker data to one node. |
| Deleted the `config:` block | See below — it never did anything. |
| Added comments explaining all three | These are non-obvious traps that already cost a year. |

**Verified after applying:**
- ArgoCD `Unknown` → **`Synced` / `Healthy`**
- PVC `mosquitto-data` **Bound**, 1Gi, `longhorn` (attached on charliepi)
- Pod **`1/1 Running`**, 0 restarts; `/mosquitto/data` mounted, writable, `persistence true`
- Other 4 ArgoCD apps still Synced/Healthy; certificates still **15/15 True**

---

## Finding: the `config:` block was dead for 9 months

The `config: mosquitto.conf:` block added 2025-11-28 **was silently ignored**.
Chart 4.4.0 has no top-level `config` value — it *generates* `mosquitto.conf`
itself from `auth` / `persistence` / `perListenerSettings`
(`templates/configmap.yaml`). Confirmed against the live ConfigMap: it contained
none of the intended retention lines.

**So these never applied and still do not:**
`max_queued_messages 1000`, `max_inflight_messages 20`, `max_queued_bytes 100MB`,
`message_expiry_interval 604800`.

Removed rather than left looking functional (user's call). To actually get them,
override `persistence."mosquitto-config"` to mount a ConfigMap of your own:

```yaml
persistence:
  mosquitto-config:
    type: custom
    mountPath: /mosquitto/config/mosquitto.conf
    subPath: mosquitto.conf
    volumeSpec:
      configMap:
        name: mosquitto-custom-config
```

---

## Clients: recovered untouched, but still on the public-IP hairpin

The user chose *homelab-repo-only*; the clients were left alone to see if they'd
self-recover. They did, all three within ~4 min of the broker coming up —
`room-checker` on a genuine unassisted retry (restart counter 2194 → 2195), not a
forced restart. All three are confirmed connected in the broker log. They reach it
via `mqtt.leetserve.com`, which resolves to the public IP `96.228.35.135` and
hairpins back through the router.

That path works today, but it is still the fragile arrangement flagged earlier.
Repointing costs differ sharply, which is why it wasn't bundled in:

| Client | Broker set where | Cost to repoint |
|---|---|---|
| `reap` | `BROKER` env in `~/repos/reap/deploy/reap.yaml:24` (also a flag default in `main.go:46`) | **Cheap** — manifest edit, no rebuild. Note: that repo has uncommitted changes to `mqttc.go` / `reap.go`. |
| `event-checker` | **hardcoded** `app/config.py:11`, no env override | Code change + image rebuild + Skaffold redeploy |
| `room-checker` | **hardcoded** `app/config.py:8`, no env override | Code change + image rebuild + Skaffold redeploy |

Target if/when done: `mosquitto.mosquitto.svc.cluster.local:1883`.

Note `eventchk` is also running a **date window that expired in Nov 2024**
(`START_DATE=2024-11-01`, `END_DATE=2024-11-29`), so it connects but likely does
nothing useful.

---

## Not recoverable: the old mosquitto data

All 8 PVs in the cluster are Bound to other claims — **no released or orphaned PV**
survived the original `mosquitto-data`. The broker started on an empty volume.
Nothing to restore; noted so nobody goes looking.

---

## Next steps

1. **plant-shop** — ext4 corruption (`Resize inode not valid`, `RUN fsck MANUALLY`).
   Needs a manual `fsck` against `/dev/longhorn/pvc-dd559b8a-...` from a
   maintenance pod. Data risk — do backups first.
2. **Repoint the three MQTT clients** off the public-IP hairpin (table above).
3. **Longhorn disk imbalance** — betapi 125GB / charliepi 62GB / alphapi 31GB with
   `default-replica-count: 2` and strict anti-affinity. This combination already
   broke the Prometheus expansion and will do it again.
4. **Cleanup** — delete `default/rwx-debug-1765122160` (leftover debug pod, 6583 restarts).
5. **Bring 4 out-of-repo ingresses into this repo** (`eventchk`, `roomchk`,
   `travel-happy`, `fretbook-dev`) — fixed live only in session 3.
6. `patch-manager-tolerations.yaml:10` / `patch-ui-tolerations.yaml:10` still name
   the deprecated `master` key. Harmless (both also list `control-plane` on line 13).

---

## Previously completed (sessions 1–3)

- **Off-network access restored.** `alphapi` carried the deprecated
  `node-role.kubernetes.io/master` taint while `svclb-traefik` tolerates
  `control-plane` — keys didn't match, so svclb never scheduled there and the
  router forwarded to a closed port. Taint swapped; `svclb-traefik` 2 → 3.
- **Certificates 15/15 green** (was 10 failing). Every ingress now uses
  `letsencrypt-aws-prod` (DNS01).
- **Prometheus recovered** from a 2772-restart crashloop. `retentionSize: 5GiB` on a
  `5Gi` volume left no headroom for WAL/compaction. Now `6GiB` on `10Gi`; the
  expansion needed `numberOfReplicas` dropped to 1.
- **`make iot` review gate.** `make diff` (secrets by name only) → `make approve`
  (`[y/N]`, fails closed without a TTY, `AUTO_APPROVE=1` skips) → apply.
  `make apply-iot` bypasses. Added after finding a blind apply would have silently
  upgraded ArgoCD and dropped 11 people from the forward-auth whitelist.
- **ArgoCD pinned to v3.2.1** — `namespace-argocd/kustomization.yaml:6` had tracked
  floating `stable`, so the running version depended on when `make iot` last ran.
- **Priorities:** control plane first (DNS, ingress, off-network access to
  prototypes behind ingress auth); monitoring second; stateful/Longhorn last.
  SSO was a spike, not a priority.

---

## Handy commands

```bash
kubectl --context alphapi get certificate -A
kubectl --context alphapi -n argocd get applications
kubectl --context alphapi -n kube-system get ds | grep svclb   # expect DESIRED 3

# render an ArgoCD Helm Application locally before applying — this is what
# would have caught the mosquitto bug a year ago
helm template mosquitto ./mosquitto --namespace mosquitto -f values.yaml

# per-node port reality check (use exit code, not just http_code)
for ip in 192.168.1.84 192.168.1.26 192.168.1.234; do
  printf "%-15s :443 -> " "$ip"
  curl -sk --max-time 5 -o /dev/null -w 'http=%{http_code}' "https://$ip/"; echo " exit=$?"
done
```
