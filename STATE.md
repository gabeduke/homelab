# Homelab — session state

**Last updated:** 2026-09-08 (session 3 — COMPLETE, pushed) · **Branch:** main · **Cluster:** `alphapi` (k3s v1.35.5)

---

## TL;DR — session complete, everything committed and pushed

**Off-network access restored**, **15/15 certificates green** (was 10 failing),
**Prometheus recovered** from a 2772-restart crashloop, and `make iot` now has a
diff + explicit-approval gate.

Branch `main` is **in sync with `origin/main`** at `3dc66bd`. Working tree clean.

> **History was rewritten before pushing.** GitHub secret scanning blocked the
> push on a *placeholder* Slack webhook (`T00000000/B00000000/XXXX…` — Slack's own
> documentation example, in a `# Format:` comment, no real credential). It was
> sanitized to `<WORKSPACE_ID>/<CHANNEL_ID>/<TOKEN>`, which required amending the
> commit that introduced it. **Two SHAs changed:** `8e5a49e → ccf36df` and
> `88b3a62 → 3dc66bd`. Verified the only content difference was that single line.
> If any other clone or worktree of this repo exists, it needs a fresh pull.

Priorities recorded from the user: **control plane first** — DNS management,
central ingress, and off-network access to quickly-prototyped apps behind ingress
auth. Monitoring second (only if it fits Pi constraints). Stateful/Longhorn last.
**SSO was a spike and is not a priority.**

---

## The headline fix (done)

`alphapi` was tainted with the **deprecated** `node-role.kubernetes.io/master=true:NoSchedule`.
`svclb-traefik` tolerates `node-role.kubernetes.io/control-plane` with
`operator: Exists`. Keys didn't match → svclb never scheduled on alphapi →
alphapi bound no ports → the router's forward hit a closed port.

`scripts/control-plane/run.sh:11` **already had the fix** (uncommitted), but
`INSTALL_K3S_EXEC` only applies on a fresh k3s install, so the running node
never picked it up. Applied live:

```bash
kubectl taint node alphapi node-role.kubernetes.io/control-plane=true:NoSchedule --overwrite
kubectl taint node alphapi node-role.kubernetes.io/master:NoSchedule-
```

Verified: `svclb-traefik` DESIRED **2 → 3**; alphapi :80/:443 went
**connection-refused → 404** (Traefik answering); `https://96.228.35.135/` → 404;
`auth.leetserve.com` → 307 with `tls=0`.

Note: the `control-plane=true` **label** was already present, so system-upgrade
plans (label-based) were never affected.

---

## Done this session

| Change | Where |
|---|---|
| Taint swapped `master` → `control-plane` | live cluster; repo already correct at `run.sh:11` |
| `argocd-tls` + `longhorn-tls` → DNS01, both issued | live + `argocd-ingress.yaml:9`, `longhorn-ingress.yaml:9` |
| `auth-selector-tls` → DNS01 (session 2) | live + `auth-selector.yaml:268` |
| Recreated missing `auth-selector` Deployment (session 2) | live |
| Longhorn `taint-toleration` → `control-plane` | `longhorn-settings.yaml:6` |
| node-exporter toleration → `control-plane` | `prom-stack.yaml:153` |

All repo edits are **uncommitted**, alongside the ~25 files already in flight.

`patch-manager-tolerations.yaml:10` and `patch-ui-tolerations.yaml:10` still name
`master`, but both list `control-plane` on line 13 too, so they still work.

---

## Corrected diagnoses (previous sessions had these wrong)

**Prometheus is out of disk, not out of CPU.**
```
opening storage failed: open /prometheus/wal/00001095: no space left on device
```
`retentionSize: 5GiB` on a `storage: 5Gi` volume — the retention cap equals the
**whole disk**, leaving no headroom for WAL, compaction, or ext4's reserve. It
fills the volume before retention ever triggers. The uncommitted CPU-limit and
`evaluationInterval` tuning in `prom-stack.yaml` would **not** have fixed this.

Fix: set `retentionSize` to ~70–80% of the volume (e.g. `3GiB` on 5Gi), or expand
the volume. Because the disk is *already* full, Prometheus cannot start to
enforce a new limit — the volume likely needs expanding (Longhorn supports it) or
the WAL cleared before the new setting can take effect.

**HTTP01 works again.** With alphapi serving :80, the original root cause is
gone. DNS01 is still the better default (survives ISP :80 blocking, node changes,
enables wildcards) but is no longer strictly required.

**Longhorn is healthier than assumed.** All 3 nodes Ready and schedulable; 6 of 8
volumes healthy. Only `pvc-fc1353bc` (Prometheus, 5Gi) is **degraded**, and the
two `unknown` ones are detached wikileet volumes. This is not a broken stack —
it is two specific volume problems.

**plant-shop is filesystem corruption, not Longhorn.**
`Resize inode not valid ... UNEXPECTED INCONSISTENCY; RUN fsck MANUALLY`
(x7013 over 9d). Needs a manual `fsck` against
`/dev/longhorn/pvc-dd559b8a-...` from a maintenance pod. Data risk — do it
deliberately, with the backup work finished first.

---

## BLOCKED: permission classifier

These were denied mid-session and are the only reason the cert work is unfinished:

- `kubectl delete certificaterequest --all` / `delete challenge --all` (bulk delete)
- `kubectl annotate ingress ...` on `eventchk` — **denied even as a single command
  identical in shape to ones that succeeded moments earlier for argocd/longhorn**

Remaining certs need either a Bash permission rule for `kubectl` or a manual run:

```bash
kubectl --context alphapi -n eventchk     annotate ingress event-checker-ingress     "cert-manager.io/cluster-issuer=letsencrypt-aws-prod" --overwrite
kubectl --context alphapi -n roomchk      annotate ingress room-checker-ingress      "cert-manager.io/cluster-issuer=letsencrypt-aws-prod" --overwrite
kubectl --context alphapi -n travel-happy annotate ingress travel-calculator-ingress "cert-manager.io/cluster-issuer=letsencrypt-aws-prod" --overwrite
kubectl --context alphapi -n fretbook-dev annotate ingress fretbook                  "cert-manager.io/cluster-issuer=letsencrypt-aws-prod" --overwrite
```

The 3 `monitoring/` certs are ArgoCD-owned with `selfHeal: true` — annotating the
Ingress gets reverted; they must change through the `prom-stack` Application's
inline Helm values (`docs/tls-http01-outage.md` runbook step 2).

Runbook **step 3 is unnecessary** — changing the issuer sets `IncorrectIssuer`
and cert-manager reissues within ~14s, ignoring the backoff. Proven three times
now; each cert went green in ~90s.

---

## Next steps

1. **Four out-of-repo ingresses → DNS01** (commands above), then persist by
   bringing those manifests into this repo.
2. **Prometheus:** expand the volume and set `retentionSize` to ~3GiB. This is
   the "make monitoring fit a Pi" work — and the real fix, unlike the CPU tuning.
3. **Two default StorageClasses** — `local-path (default)` *and* `longhorn
   (default)`. Kubernetes picks arbitrarily between them; this is a likely root
   cause of the recurring nondeterministic stateful failures. Pick one:
   `kubectl patch sc <name> -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'`
4. **Commit the working tree.** ~25 files are in flight and the user confirmed
   they represent intended state. `make iot` is now reasonable *after* review —
   the earlier "do not run it" warning was based on assuming the tree was
   unvetted.
5. **mosquitto:** PVC `mosquitto-data` does not exist → Pending → `reap`,
   `eventchk`, `roomchk` crashloop. They also reach the broker at the **public
   IP** `96.228.35.135:1883`; repoint to
   `mosquitto.mosquitto.svc.cluster.local:1883` to decouple from the port-forward.
6. **plant-shop:** manual `fsck` (see above), after backups.
7. **Cleanup:** delete `default/rwx-debug-1765122160` — leftover debug pod at
   **6583 restarts**.

---

## Cluster health snapshot

Healthy and serving your stated priorities: **external-dns** Running,
**Traefik** Running with LoadBalancer IP, **cert-manager** working with DNS01
proven, all 3 nodes Ready.

Still failing: `prometheus` (disk full), `mosquitto` (Pending) → `reap` /
`eventchk` / `roomchk`, `plant-shop` (fsck).

Node OS drift: alphapi Ubuntu 22.04 / kernel 5.15; workers 25.10 / 6.17.
Supported to 2027 — drift, not urgency.

---

## Handy commands

```bash
kubectl --context alphapi get certificate -A
kubectl --context alphapi -n kube-system get ds | grep svclb   # expect DESIRED 3

# per-node port reality check (use exit code, not just http_code)
for ip in 192.168.1.84 192.168.1.26 192.168.1.234; do
  printf "%-15s :443 -> " "$ip"
  curl -sk --max-time 5 -o /dev/null -w 'http=%{http_code}' "https://$ip/"; echo " exit=$?"
done
```

---

## `make iot` LANDMINES — RESOLVED 2026-09-07 (session 3)

A `kubectl diff -k clusters/iot` originally showed **15 changed resources**, two
of them unintended. Both are now fixed; the diff is down to **5, all intentional**.

**1. Auth whitelist regression — FIXED.** Live `traefik-forward-auth` had **25**
whitelisted emails, the repo had **14**. Applying would have removed
`arlo.ellington.duke`, `luna.mae.duke`, `noam.river.duke`, `thecocosanchez`,
`marcjsanchez`, `mduke033`, `mrjeff2u`, `vikkikrekler`, `nocherobot`,
`MsJenDuke@aol.com`, `cocadukes1@aol.com`. The live cluster was **ahead of the
repo** — the manifest was likely rebuilt from an older copy during the Facebook
removal. Backfilled from the live deployment into `traefik-fwd-auth.yaml:57`;
verified byte-identical.

**2. ArgoCD floating version — FIXED.** `namespace-argocd/kustomization.yaml:6`
pointed at `.../argo-cd/stable/manifests/install.yaml`. **`stable` floats**, so
every `make iot` pulled whatever upstream stable was that day — the cluster's
ArgoCD version was a function of *when you last ran it*. This is a strong
candidate for the recurring drift. Now pinned to **v3.2.1** (what is actually
running), so applying is a no-op and upgrades become a deliberate one-line bump.

Remaining 5 diffs, all intended: Facebook provider removal from forward-auth;
prom-stack issuers + retention/storage; longhorn `taint-toleration` →
`control-plane`; argocd/longhorn ingress `last-applied-configuration` refresh.

---

## Certificates: ALL GREEN

**15/15 `True`** (was 10 failing). The user ran the four out-of-repo annotations
and `kubectl apply -f clusters/iot/namespace-argocd/prom-stack.yaml`; all seven
remaining certs issued within ~135s. Every ingress in the cluster now uses
`letsencrypt-aws-prod` (DNS01). All six issuer references in the repo match.

---

## Prometheus: FIXED

Root cause was `retentionSize: 5GiB` on a `5Gi` volume — the retention cap equalled
the whole disk, so it filled before retention ever triggered
(`no space left on device`, **2772 restarts**).

Fix, applied end to end:
1. Repo: `retentionSize: 6GiB` on `storage: 10Gi` (`prom-stack.yaml:52,62`).
2. Live PVC patched 5Gi → 10Gi. Longhorn initially **refused** the expansion:
   `ReplicaSchedulingFailure: disks are unavailable; insufficient storage`.
3. Root cause of *that*: the volume wanted `numberOfReplicas: 2` with
   `replica-soft-anti-affinity: false`, so the second replica needed a node other
   than betapi — but charliepi was excluded by the 25%
   `storage-minimal-available-percentage` floor (78.3% full) and alphapi was
   0.1GB short of the 10GB required.
4. User patched the volume to `numberOfReplicas: 1` (TSDB is recreatable).
   Robustness went degraded → **healthy**, `Scheduled` → `True`, and the pending
   expansion completed on the resizer's next retry.

**Result: `2/2 Running`, zero restarts for 88+ min, `/prometheus` at 43%
(4.2G of 9.8G).**

The underlying disk imbalance remains (betapi 125GB / charliepi 62GB /
alphapi 31GB) with `default-replica-count: 2` and strict anti-affinity — that
combination will keep producing this failure for other volumes.

---

## `make iot` now has a review gate

Added to the Makefile, and the reason it exists: this session found two changes
that a blind `make iot` would have pushed silently — an unpinned ArgoCD upgrade
(v3.2.1 → v3.5.2) and 11 people dropped from the forward-auth whitelist. Neither
was visible without diffing first.

- `make diff` — shows what would change, applies nothing. Secrets are reported
  **by name only**; their values are never printed to the terminal. (The secrets
  diff is client-side, matching how `make secrets` actually applies; the
  `clusters/iot` diff is server-side, matching its apply.)
- `make approve` — interactive `[y/N]` prompt naming the target context.
  **Fails closed**: aborts if there is no TTY. `AUTO_APPROVE=1` skips it.
- `make iot` — now `diff → approve → namespaces → secrets → apply-iot`.
  Order matters: the gate runs *before* anything mutates, since `namespaces` and
  `secrets` both write. Do not run with `make -j`.
- `make apply-iot` — bypasses the gate entirely.

All four paths were tested: diff-only, no-TTY abort, `AUTO_APPROVE=1`, and a
full 135-resource apply.

---

## Cluster state

**Certificates: 15/15 `True`** (from 10 failing). Every ingress uses
`letsencrypt-aws-prod` (DNS01); all six repo references match.

**Off-network access restored** via the `master` → `control-plane` taint swap on
alphapi.

Still failing, all previously known and out of scope:

| Workload | Problem |
|---|---|
| `mosquitto` | PVC `mosquitto-data` does not exist → `Pending` |
| `reap`, `eventchk`, `roomchk` | depend on mosquitto; also reach the broker at the **public IP** `96.228.35.135:1883` rather than `mosquitto.mosquitto.svc.cluster.local:1883` |
| `plant-shop` | ext4 corruption (`Resize inode not valid`); needs a manual `fsck`, after backups |

---

## Next steps

1. **mosquitto** — recreate the PVC, then repoint the three clients at the
   in-cluster service so they stop depending on the port-forward.
2. **Two default StorageClasses** — `local-path` *and* `longhorn` are both marked
   default; Kubernetes picks arbitrarily. Likely another source of stateful
   nondeterminism.
3. **plant-shop** — manual `fsck`, after the backup work is finished.
4. **Longhorn disk imbalance** — consider `default-replica-count: 1` for
   recreatable data, or free space on charliepi/alphapi.
5. **Cleanup** — delete `default/rwx-debug-1765122160` (6583 restarts).
6. **Bring the four out-of-repo ingresses into this repo** (`eventchk`,
   `roomchk`, `travel-happy`, `fretbook-dev`) — they were fixed live only.
