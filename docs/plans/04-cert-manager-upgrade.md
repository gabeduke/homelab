# Plan 04 — cert-manager 1.14.5 → 1.21.x

**Finding:** new in session 6 (surfaced while checking prerequisites for the k3s bump)
**Risk: HIGH** — this component issues every TLS cert in the cluster, and has an outage history
**Cluster impact:** cert-manager restart + CRD upgrade · **Needs SSH:** no (ArgoCD-driven)
**Blocks: plan 05** · **Blocked by:** nothing

The review started out treating cert-manager as a footnote to the k3s upgrade.
The research inverted that: **cert-manager is the gating dependency, and it is the
single most out-of-date thing in the cluster.**

---

## Why this is now the blocker

Verified against the [cert-manager supported releases](https://cert-manager.io/docs/releases/) matrix:

| cert-manager | Released | EOL | Supported Kubernetes |
|---|---|---|---|
| **1.14** (deployed) | Feb 2024 | **Oct 2024** | ~1.23 → 1.29 |
| 1.20 | Mar 2026 | rel. of 1.22 | 1.32 → 1.35 |
| **1.21** | Jul 2026 | rel. of 1.23 | **1.33 → 1.36** |

Two things fall out of that table:

1. **1.21 is the only release that supports Kubernetes 1.36.** Plan 05 bumps k3s
   to v1.36.4+k3s1. Doing that first would leave the cert issuer outside its
   supported range on a cluster where TLS has already broken once.
2. **The current deployment is already unsupported.** cert-manager 1.14 went EOL
   in **October 2024** — nearly two years ago, no security fixes — and the
   cluster runs Kubernetes 1.35, six minors past 1.14's ceiling. It works
   (certificates are 15/15 green) but that is luck, not support.

So this upgrade is worth doing on its own merits even if the k3s bump never happens.

---

## What actually breaks — checked, not assumed

The v1.21.0 release notes list three breaking changes and a set of removed Helm
values. Each was checked against this cluster's actual configuration.

### 1. Removed Helm values → **not affected**

v1.21 sets `additionalProperties: false` in the values schema, so *any*
unrecognised key is a hard validation error on upgrade. The removed keys are
`prometheus.servicemonitor.targetPort`, `prometheus.servicemonitor.path`, and
`prometheus.podmonitor.path`.

Current values in `clusters/iot/namespace-argocd/cert-manager.yaml`:

```yaml
installCRDs: true
prometheus:
  enabled: false
global:
  leaderElection:
    namespace: cert-manager
podDnsConfig:
  nameservers: [8.8.8.8, 8.8.4.4]
```

None of the removed keys are set. Verified by resolving the actual
`values.schema.json` from the `cert-manager-v1.21.1.tgz` chart — every key above
is still present in `$defs/helm-values/properties`, including `prometheus.enabled`.

### 2. `installCRDs` → **still works, but migrate it**

Also verified from the 1.21.1 schema:

```json
"helm-values.installCRDs": {
  "default": false,
  "description": "This option is equivalent to setting crds.enabled=true and
                  crds.keep=true. Deprecated: use crds.enabled and crds.keep instead.",
  "type": "boolean"
}
```

It validates and behaves identically, so the upgrade will not fail on it. Migrate
anyway while you are in the file:

```yaml
crds:
  enabled: true
  keep: true      # what installCRDs:true implied -- do not let CRDs be deleted
```

`keep: true` matters here: the ArgoCD Application has `prune: true`, and CRD
deletion would take every `Certificate` and `ClusterIssuer` with it.

### 3. `tokenrequest` RBAC removal → **not affected**

v1.21 stops shipping the Role/RoleBinding granting `serviceaccounts/token: create`.
This only affects issuers that use `serviceAccountRef` for ambient credentials.
The Route53 issuer here uses static keys from a Secret:

```yaml
route53:
  accessKeyIDSecretRef:     {name: cert-manager, key: aws_access_key_id}
  secretAccessKeySecretRef: {name: cert-manager, key: aws_secret_access_key}
```

No `serviceAccountRef` anywhere in `namespace-cert-manager/`. Unaffected.

### 4. `cert-manager-edit` ClusterRole narrowed → **not affected**

Only matters if something outside cert-manager creates `Challenge`/`Order`
resources directly. Nothing here does.

### 5. Metrics service port renamed → **not affected**

`tcp-prometheus-servicemonitor` → `http-metrics`. `prometheus.enabled: false`,
and there is no ServiceMonitor for cert-manager in `namespace-monitoring/`.

### The real risk is not in the release notes

It is the **CRD upgrade across seven minor versions under ArgoCD with
`selfHeal: true` and `prune: true`.** Helm-managed CRDs plus ArgoCD auto-sync is
a known-awkward combination ([issue #8771](https://github.com/cert-manager/cert-manager/issues/8771)).
The mitigation below is to take auto-sync out of the loop for the duration.

---

## Execution

### Step 0 — back up every cert-manager resource

Non-negotiable. These are the objects that, if lost, take out ingress TLS cluster-wide.

```bash
mkdir -p /tmp/cm-backup && cd /tmp/cm-backup
for k in clusterissuers issuers certificates certificaterequests orders challenges; do
  kubectl get "$k" -A -o yaml > "$k.yaml"
done
kubectl get secret -A -o yaml \
  | python3 -c "import sys,yaml;d=yaml.safe_load(sys.stdin);d['items']=[i for i in d['items'] if i['type']=='kubernetes.io/tls'];print(yaml.dump(d))" \
  > tls-secrets.yaml
kubectl get crd -o name | grep cert-manager.io | xargs -n1 kubectl get -o yaml > crds.yaml
kubectl get cert -A > /tmp/pre-certs.txt      # the 15/15 baseline
```

`tls-secrets.yaml` is the important one — with those, certificates survive even a
botched controller upgrade, because the secrets are what Traefik actually serves.

### Step 1 — disable auto-sync so the CRD upgrade is not fought mid-flight

```bash
kubectl -n argocd patch application cert-manager --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

### Step 2 — edit the Application

In `clusters/iot/namespace-argocd/cert-manager.yaml`:

```yaml
    targetRevision: "1.21.1"        # was 1.14.5
    helm:
      values: |-
        crds:                       # was: installCRDs: true
          enabled: true
          keep: true
        prometheus:
          enabled: false
        global:
          leaderElection:
            namespace: cert-manager
        podDnsConfig:
          nameservers:
            - 8.8.8.8
            - 8.8.4.4
```

Keep `podDnsConfig` — it forces public resolvers for the DNS01 self-check, which
matters on a network that hairpins its own domain.

### Step 3 — render before applying

```bash
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm template cert-manager jetstack/cert-manager --version 1.21.1 \
  -n cert-manager -f <(cat <<'EOF'
crds: {enabled: true, keep: true}
prometheus: {enabled: false}
global: {leaderElection: {namespace: cert-manager}}
podDnsConfig: {nameservers: [8.8.8.8, 8.8.4.4]}
EOF
) > /tmp/cm-1.21.1.yaml
echo "exit=$?"    # non-zero here means a values schema error -- stop and read it
```

A clean render is the cheap proof that the values survive `additionalProperties: false`.

### Step 4 — sync, watching

```bash
make diff                      # review; then
kubectl -n argocd patch application cert-manager --type merge \
  -p '{"spec":{"source":{"targetRevision":"1.21.1"}}}'   # or apply the repo change
argocd app sync cert-manager   # or: kubectl -n argocd patch ... to trigger

kubectl -n cert-manager get pods -w
```

Expect `cert-manager`, `cert-manager-webhook`, `cert-manager-cainjector` to roll,
and a `startupapicheck` Job to run once and complete.

### Step 5 — verify against a staging issuer first

Do **not** validate by deleting a production certificate — Let's Encrypt rate
limits will bite. The repo already has `letsencrypt-staging`:

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: {name: cm-upgrade-canary, namespace: default}
spec:
  secretName: cm-upgrade-canary-tls
  dnsNames: ["canary.leetserve.com"]
  issuerRef: {name: letsencrypt-staging, kind: ClusterIssuer}
EOF

kubectl describe cert cm-upgrade-canary        # watch to Ready=True
kubectl delete cert cm-upgrade-canary; kubectl delete secret cm-upgrade-canary-tls
```

> `letsencrypt-staging` solves via **http01/traefik**, whereas the production
> issuer in use is `letsencrypt-aws-prod` (**dns01/route53**). The canary proves
> the controller and CRDs work; it does not exercise the Route53 path. To test
> that too, temporarily point the canary at a copy of the AWS issuer aimed at
> the staging ACME server.

### Step 6 — confirm the fleet is intact, then re-enable auto-sync

```bash
kubectl get cert -A | diff /tmp/pre-certs.txt -    # still 15/15 Ready
kubectl get clusterissuer                          # all Ready
kubectl -n cert-manager logs deploy/cert-manager --tail=50 | grep -i error

kubectl -n argocd patch application cert-manager --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

Certificates are only re-issued near expiry, so "15/15 Ready" immediately after
the upgrade proves the CRDs and existing state survived — **not** that issuance
works. The canary in step 5 is what proves issuance.

### Rollback

```bash
kubectl -n argocd patch application cert-manager --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null},"source":{"targetRevision":"1.14.5"}}}'
argocd app sync cert-manager
kubectl apply -f /tmp/cm-backup/clusterissuers.yaml
```

Because `crds.keep: true` prevents CRD deletion, and the TLS Secrets are backed
up and untouched by a controller downgrade, ingress keeps serving throughout even
if the controller itself is unhealthy. Downgrading CRDs is the one genuinely
awkward path — if `helm` refuses, restore from `/tmp/cm-backup/crds.yaml`.

---

## Should you step through intermediate versions?

The docs do not forbid a direct v1.x jump, and every API in use is `cert-manager.io/v1`,
stable since v1.0. A single 1.14.5 → 1.21.1 hop is the recommendation: each
intermediate release means another CRD apply, another webhook restart, and
another window where issuance is degraded. One well-backed-up jump has a smaller
total exposure than seven small ones.

If the direct jump fails at the CRD step, fall back to 1.14.5 → **1.17** → 1.21.1.

---

## Commit

```
Upgrade cert-manager 1.14.5 -> 1.21.1

1.14 went EOL in October 2024 and supports Kubernetes up to ~1.29; the cluster
runs 1.35. 1.21 is also the only release supporting Kubernetes 1.36, so this is
a prerequisite for the k3s bump in plan 05.

Values checked against the 1.21.1 values.schema.json: none of the keys removed
in 1.21 are set here, and the three breaking changes (tokenrequest RBAC,
cert-manager-edit, metrics port) do not apply to this configuration.

Migrate the deprecated installCRDs to crds.enabled/crds.keep; keep:true matters
because the ArgoCD Application prunes.
```

---

## Outcome — executed 2026-09-08 (session 8)

Upgrade completed on the first attempt, no rollback, no fallback through 1.17.
Live: `quay.io/jetstack/cert-manager-{controller,cainjector,webhook}:v1.21.1`,
all three `1/1 Running` with **zero restarts**. Post-upgrade state verified
identical to the pre-upgrade baseline: 3 nodes Ready v1.35.5+k3s1, certs
**15/15 True** (byte-identical `kubectl get cert -A` output), 4 ClusterIssuers
Ready, 5 ArgoCD apps Synced/Healthy, `longhorn` still the sole default
StorageClass, `svclb-traefik` 3/3. No errors in the controller or webhook logs.

### Correction 1 — the CRD risk was overstated

This plan called "the CRD upgrade across seven minor versions under ArgoCD with
`selfHeal` and `prune`" the real risk. Measured, it is close to a non-event:

- Rendering both charts with this cluster's values and diffing the object sets
  gives **48 objects vs 48, with zero additions and zero removals.** With
  `prune: true` there was therefore nothing to prune. ArgoCD's own refresh
  agreed: 44 resources OutOfSync (the 48 less the 4 `startupapicheck` hook
  objects), none marked for pruning.
- All 6 CRDs are the same 6, each with a **single `v1` version, served and
  storage, `conversion: None`** on both sides. So this is an in-place schema
  update on one unchanged version — no conversion webhook, no storage-version
  migration, nothing to re-encode.

Do this same render-and-diff before plan 05. It converts "seven minors is scary"
into a countable fact in about two minutes.

### Correction 2 — do NOT `kubectl apply` the repo file at step 4

Step 4 offers "or apply the repo change" as an alternative to patching. **That
silently undoes step 1.** The repo file carries `syncPolicy.automated`, so
applying it re-enables auto-sync mid-upgrade — exactly what step 1 exists to
prevent. Patch the source fields only:

```bash
kubectl -n argocd patch application cert-manager --type merge \
  -p '{"spec":{"source":{"targetRevision":"1.21.1","helm":{"values":"..."}}}}'
```

Build that patch **from the repo file** so live and repo cannot drift, then
re-apply the full file (or `make iot`) after auto-sync is back on. Verified
afterwards with `kubectl diff -f clusters/iot/namespace-argocd/cert-manager.yaml`
→ no spec difference.

### Correction 3 — the step 5 http01 canary would litter production DNS

Do not run it as written. `canary.leetserve.com` does not resolve, and
external-dns runs `--policy=upsert-only --source=ingress`: it would create a
record for the http01 solver Ingress and then **never delete it**, leaving a
permanent stale `canary.leetserve.com` A record plus its TXT registry entry.

What was run instead — and it is the better test, as this plan's own note
suggests: a temporary `ClusterIssuer` pointing at the **staging ACME server with
the Route53 dns01 solver**, copied from `letsencrypt-aws-prod` (distinct
`privateKeySecretRef` so the existing staging account key is untouched).
cert-manager creates and deletes the `_acme-challenge` TXT record itself, so it
self-cleans — confirmed absent afterwards via `dig`.

Both canaries passed:

| Canary | Proves | Result |
|---|---|---|
| `selfsigned` ClusterIssuer | Certificate → CertificateRequest → Secret on the new CRDs | Ready=True in ~4s |
| staging ACME + Route53 dns01 | Order/Challenge CRDs, Route53 API with the static-key Secret, `podDnsConfig` self-check resolvers, outbound ACME | challenge `pending → valid`, Ready=True in ~110s; real cert from `(STAGING) Ersatz Emmer YR2` |

The dns01 canary is what makes "15/15 Ready" meaningful — it exercises the
solver path the production issuer actually uses. All canary objects deleted;
the 4 original ClusterIssuers are intact.

### Notes for plan 05

- **The STATE.md gap is closed.** `global.leaderElection.namespace` and
  `podDnsConfig` were the two keys this plan's research never checked. Both are
  present in the 1.21.1 `values.schema.json` (whose root really is
  `additionalProperties: false`), as are `crds.enabled`, `crds.keep`,
  `installCRDs` and `prometheus.enabled`. `helm template` exits 0.
- Breaking change #3 was moot in both directions: **1.14.5 does not render the
  `serviceaccounts/token` RBAC either**, so there was nothing to remove.
- **There is no `argocd` CLI on the workstation.** Trigger a sync by patching
  the Application's top-level `operation` field:
  ```bash
  kubectl -n argocd patch application cert-manager --type merge -p '{"operation":
    {"initiatedBy":{"username":"plan-04"},
     "sync":{"revision":"1.21.1","prune":false,"syncStrategy":{"hook":{}}}}}'
  ```
- Every jetstack chart version carries a leading `v` (`v1.21.1`). A bare
  `targetRevision: "1.21.1"` still resolves because ArgoCD treats it as a semver
  constraint — which is why `"1.14.5"` worked. Keep the existing no-`v` style.
- `make iot` was deliberately **not** used: baseline `make diff` showed two
  unrelated drifts it would also have pushed (a mosquitto values *comment*, and
  `wikileet/django-app-secrets`). Both are pre-existing; see the STATE.md backlog.
- Backups from step 0 are in `/tmp/cm-backup` (25 TLS secrets, 4 ClusterIssuers,
  6 CRDs) — `/tmp` does not survive a reboot, so re-take them for plan 05.

**Plan 05 is now unblocked.** cert-manager 1.21 supports Kubernetes 1.33–1.36.
