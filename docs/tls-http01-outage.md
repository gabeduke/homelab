# TLS outage: every HTTP01 certificate has been expired since April 2026

**Investigated:** 2026-09-07 · **Cluster:** `alphapi` (k3s v1.35.5) · **Status:** diagnosed; `auth-selector` fixed and verified, 9 certs remain

---

## Summary

Ten of fifteen TLS certificates in the cluster expired in April/May 2026 and
have never renewed. The cause is not cert-manager, DNS, or Let's Encrypt — it is
a single misrouted port.

`alphapi` carries the `node-role.kubernetes.io/master=true:NoSchedule` taint, so
the `svclb-traefik` DaemonSet only schedules on `betapi` and `charliepi`. That
means **`alphapi` binds neither :80 nor :443**. The router's port-forward still
points at it, so every inbound HTTP request — including ACME HTTP01 validation —
is refused.

The split across issuers is exact, and it is the proof:

| ClusterIssuer | Challenge | Certificates | State |
|---|---|---|---|
| `letsencrypt-prod` | HTTP01 | 10 | **all expired** Apr–May 2026 |
| `letsencrypt-aws-prod` | DNS01 (Route53) | 3 | **all healthy**, valid to 2026-10-22 |

DNS01 never touches inbound connectivity, which is why those three kept
renewing while everything else silently died.

---

## Evidence

### The nodes

```
alphapi    192.168.1.84   :80  -> connection refused
alphapi    192.168.1.84   :443 -> connection refused
betapi     192.168.1.26   :80  -> 404   (Traefik answering — correct)
betapi     192.168.1.26   :443 -> 404
charliepi  192.168.1.234  :80  -> 404
charliepi  192.168.1.234  :443 -> 404
```

`svclb-traefik-f96d25e3` reports `DESIRED 2` on a three-node cluster — it cannot
tolerate the master taint, so alphapi is simply not in the set.

### The ACME failure

```
Error accepting authorization: acme: authorization error for
longhorn.leetserve.com: 400 urn:ietf:params:acme:error:connection:
96.228.35.135: Fetching
http://longhorn.leetserve.com/.well-known/acme-challenge/... : Connection refused
```

`longhorn-tls` alone has `failedIssuanceAttempts: 126`.

### Affected certificates

| Namespace / certificate | Host | Defined in this repo? |
|---|---|---|
| `kube-system/auth-selector-tls` | auth.leetserve.com | `namespace-kube-system/auth-selector.yaml` |
| `longhorn-system/longhorn-tls` | longhorn.leetserve.com | `namespace-longhorn-system/longhorn-ingress.yaml` |
| `argocd/argocd-tls` | argocd.leetserve.com | `namespace-argocd/argocd-ingress.yaml` |
| `monitoring/grafana-tls` | grafana.leetserve.com | `namespace-argocd/prom-stack.yaml` |
| `monitoring/alertmanager-tls` | alertmanager.leetserve.com | `namespace-argocd/prom-stack.yaml` |
| `monitoring/prometheus-tls` | prometheus.leetserve.com | `namespace-argocd/prom-stack.yaml` |
| `eventchk/event-check-tls` | event-check.leetserve.com | **no** — deployed outside this repo |
| `roomchk/room-check-tls` | room-check.leetserve.com | **no** |
| `travel-happy/travel-calculator-tls` | travel-happy.leetserve.com | **no** |
| `fretbook-dev/fretbook-dev-tls` | fretbook-dev.leetserve.com | **no** |

`auth-selector-tls` is the one to fix first: it fronts `traefik-forward-auth`, so
while its certificate is invalid the Google SSO redirect fails in a browser and
**every forward-auth-protected service is effectively unreachable**, not merely
untrusted.

---

## Recommended fix: migrate everything to DNS01

Two options exist. They are not equivalent.

**Option A — repoint the router's :80/:443 forward** from `alphapi` to `betapi`
or `charliepi`. This restores HTTP01 and external reachability in one change.
It cannot be done from inside the cluster; it needs router access.

**Option B — move every ingress to `letsencrypt-aws-prod` (DNS01).** This is
the recommendation, and not merely as a workaround:

- it does not depend on any inbound port being open or forwarded
- it survives an ISP that blocks :80, and a node that stops serving it
- it is the only route to wildcard certificates
- the credentials and issuer already exist and are demonstrably working

Option A is still worth doing — external access is currently broken for
everything, and three crashlooping workloads depend on it (below). But TLS
issuance should not be coupled to it.

### Repo changes (durable, GitOps)

Change `cert-manager.io/cluster-issuer: letsencrypt-prod` to
`letsencrypt-aws-prod` in:

```
clusters/iot/namespace-kube-system/auth-selector.yaml:268
clusters/iot/namespace-longhorn-system/longhorn-ingress.yaml:9
clusters/iot/namespace-argocd/argocd-ingress.yaml:9
clusters/iot/namespace-argocd/prom-stack.yaml:104,121,204
clusters/iot/namespace-argocd/loki.yaml:68             (not currently deployed)
clusters/iot/namespace-argocd/wikileet-api.yaml:25     (not currently deployed)
clusters/iot/namespace-argocd/wikileet-api_dev.yaml:25 (not currently deployed)
```

Keep `namespace-cert-manager/letsencrypt-prod.yaml` — the issuer itself is fine
and worth retaining for when the port-forward is repaired.

### Applying

**Do not run `make iot` right now.** The working tree has substantial
uncommitted work in flight — Longhorn backup targets and storage classes, the
Prometheus tuning in `prom-stack.yaml`, `auth-selector.yaml`, gift-wiki ArgoCD
apps. `make iot` applies all of it. Apply narrowly instead — per-resource
commands are in the Runbook at the end of this document.

Note the ownership split, because it determines the method:

- `argocd-ingress`, `longhorn-ingress`, `auth-selector` and the four
  out-of-repo ingresses are plain kubectl/kustomize resources. Nothing will
  revert a direct annotation.
- The three `monitoring/` ingresses are rendered by the `prom-stack` ArgoCD
  Application, which has `selfHeal: true`. **A `kubectl annotate` on those will
  be reverted.** They must change via the Application's inline Helm values.

### Forcing re-issuance

Changing the issuer triggers a new attempt, but after 126 failures cert-manager
has backed off substantially. Delete the stale request to retry immediately:

```bash
kubectl -n <ns> delete certificaterequest <name>
```

Then watch:

```bash
kubectl get certificate -A -w
```

DNS01 validation typically takes 1–3 minutes per certificate, dominated by
Route53 propagation.

---

## Unrelated breakage found in the same pass

These are recorded for completeness. None of them block the TLS fix.

### mosquitto is Pending, and takes three apps down with it

```
0/3 nodes are available: persistentvolumeclaim "mosquitto-data" not found
```

The `mosquitto` ArgoCD app has `selfHeal: true` and sources the k8s-at-home
chart, but the PVC it expects does not exist. Consequences:

- `reap` — `dial tcp 96.228.35.135:1883: connect: connection refused`
- `eventchk` — `ConnectionRefusedError: [Errno 111]`
- `roomchk` — same

All three crashloop. Note they reach the broker via the **public IP**
`96.228.35.135:1883` rather than the in-cluster service, so they are broken
twice over: the broker is down *and* the path they use depends on the same dead
port-forward. Pointing them at `mosquitto.mosquitto.svc.cluster.local:1883`
would make them independent of both.

### plant-shop has a corrupt Longhorn volume

Stuck `ContainerCreating` for nine days:

```
MountVolume.MountDevice failed for volume "pvc-dd559b8a-...":
'fsck' found errors on device /dev/longhorn/pvc-dd559b8a-... but could not
correct them
```

This needs manual repair or a restore from backup. It carries data risk and
should not be bundled with routine maintenance. Worth noting the uncommitted
`namespace-longhorn-system/recurring-backup.yaml` and `backup-target.yaml` in
the working tree — finishing that work would make this class of failure
recoverable.

### prometheus crashloops

The `prometheus` container in
`prometheus-prom-stack-kube-prometheus-prometheus-0` is in CrashLoopBackOff
(the `config-reloader` sidecar is healthy). The uncommitted `prom-stack.yaml`
changes — raised CPU limits, `evaluationInterval: 60s`, disabled expensive
apiserver default rules — read like an in-progress fix for exactly this. Worth
finishing and applying deliberately rather than as a side effect.

### Node OS drift

`alphapi` is on Ubuntu 22.04 / kernel 5.15; `betapi` and `charliepi` are on
25.10 / kernel 6.17. 22.04 is supported until 2027, so this is drift rather
than urgency, but the control plane being the odd one out is worth closing.

---

## Priority

1. **`auth-selector-tls` → DNS01.** Smallest change, largest unlock: it repairs
   SSO for every forward-auth-protected service.
2. **The remaining five repo certificates → DNS01.**
3. **The four out-of-repo certificates → DNS01** by direct annotation, and
   ideally bring those manifests into this repo.
4. **Repoint the router's :80/:443 forward** off `alphapi`. Restores external
   access and unblocks the MQTT-dependent apps.
5. **Recreate the `mosquitto-data` PVC** and repoint the three clients at the
   in-cluster service.
6. **plant-shop volume repair** — separately, with backups in place.

---

## Runbook

Everything below is a live-cluster change. Read the ownership note above first:
the `monitoring/` ingresses are ArgoCD-owned with `selfHeal: true` and must be
changed through the Application, not the Ingress.

### Step 1 — the seven directly-managed ingresses

Nothing reverts these; they are plain kubectl/kustomize resources.

```bash
ctx=alphapi
issuer=letsencrypt-aws-prod

for e in \
  "kube-system:auth-selector" \
  "longhorn-system:longhorn-ingress" \
  "argocd:argocd-server-ingress" \
  "eventchk:event-checker-ingress" \
  "roomchk:room-checker-ingress" \
  "travel-happy:travel-calculator-ingress" \
  "fretbook-dev:fretbook"
do
  ns=${e%%:*}; ing=${e##*:}
  kubectl --context $ctx -n "$ns" annotate ingress "$ing" \
    "cert-manager.io/cluster-issuer=${issuer}" --overwrite
done
```

Do `kube-system/auth-selector` first and confirm it issues before the rest —
it is the one that unlocks SSO.

### Step 2 — prom-stack (ArgoCD-owned)

Rewrite the issuer inside the Application's inline Helm values:

```bash
kubectl --context alphapi -n argocd get application prom-stack \
  -o jsonpath='{.spec.source.helm.values}' > /tmp/prom-values.yaml

sed -i '' 's|cluster-issuer: letsencrypt-prod|cluster-issuer: letsencrypt-aws-prod|g' \
  /tmp/prom-values.yaml

python3 -c 'import json,sys; print(json.dumps({"spec":{"source":{"helm":{"values":open("/tmp/prom-values.yaml").read()}}}}))' \
  > /tmp/prom-patch.json

kubectl --context alphapi -n argocd patch application prom-stack \
  --type merge --patch-file /tmp/prom-patch.json
```

This touches only the issuer strings. It does **not** apply the uncommitted
Prometheus tuning sitting in `prom-stack.yaml` — that stays local until you
apply it deliberately.

### Step 3 — force re-issuance (VERIFIED UNNECESSARY, 2026-09-07)

**Skip this step.** Proven on `auth-selector-tls`: changing the issuer sets
`Ready=False IncorrectIssuer`, and cert-manager creates a fresh CertificateRequest
immediately rather than waiting out the backoff — a new request appeared within
14s and validated in 90s, despite 119 prior failures. Kept below only as a
fallback if a certificate genuinely stalls:

```bash
for ns in kube-system longhorn-system argocd eventchk roomchk \
          travel-happy fretbook-dev monitoring; do
  kubectl --context alphapi -n "$ns" get certificaterequest \
    -o name 2>/dev/null | xargs -r kubectl --context alphapi -n "$ns" delete
done
```

### Step 4 — verify

```bash
kubectl --context alphapi get certificate -A -w
```

DNS01 takes roughly 1–3 minutes per certificate, dominated by Route53
propagation. Then confirm one end to end:

```bash
curl -sI https://longhorn.leetserve.com | head -1
```

### Step 5 — persist it in git

The live patches above are undone by the next `make iot` unless the repo agrees.
Apply the same substitution to the seven files listed under "Repo changes",
then commit alongside your in-flight work when you are ready to apply it.
