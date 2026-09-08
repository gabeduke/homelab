# 07 — Dedicated namespace for DNSEndpoint records

**Risk:** low (additive; `upsert-only` makes the move non-destructive)
**Blocks:** nothing · **Blocked by:** nothing

---

## Context

DNSEndpoint CRs for Cloud Run–hosted apps currently live *inside the application
namespace they belong to*. That couples a piece of live control-plane state to a
workload namespace that gets torn down on ordinary cleanup.

Found on 2026-09-08 while decommissioning the stale `gift-wiki` k3s deployment.
The `wikileet` namespace held two unrelated things:

| Resource | Status |
|---|---|
| `deployment/wikileet` (2 replicas, 163d) | dead weight — no Ingress routed to it, app has served from Cloud Run for months |
| `dnsendpoint/wikileet-prod` | **live** — `giftwiki.leetserve.com` + `giftwiki-dev.leetserve.com` → `ghs.googlehosted.com` |

`kubectl delete namespace wikileet`, or `kubectl delete -k deploy/base` from the
app repo, would have taken production DNS down as a side effect of deleting a
workload that had been dead for months. The deployment was removed by hand,
resource by resource, specifically to avoid that.

Second problem: the manifest is versioned in the **application** repo
(`django-gift-wiki:deploy/cloudrun/dns-endpoint.yaml`), so cluster DNS state
lives outside homelab. Tracked there as `gabeduke/django-gift-wiki#21`.

## Verified facts

Confirmed against the running cluster, not assumed:

- external-dns `1.19.0`, ArgoCD app in namespace `externaldns`
  (`clusters/iot/namespace-argocd/external-dns.yaml`)
- `sources: [ingress, crd, service]` — **no namespace filter**, so it already
  watches every namespace. A new namespace needs *no* external-dns change.
- `domainFilters: [leetserve.com]`
- `policy: upsert-only`

**`upsert-only` is what makes this safe.** external-dns never deletes Route53
records, so moving a DNSEndpoint between namespaces cannot drop the record —
worst case it is briefly unmanaged. The same setting means stale records are
never reaped automatically, so removing a DNSEndpoint is not enough to retire a
hostname; that has to be done in Route53 by hand.

## Changes

1. Create `clusters/iot/namespace-dns-records/` in this repo:
   - `namespace.yaml` — namespace `dns-records`
   - `wikileet.yaml` — the two `giftwiki*` CNAMEs, `metadata.namespace: dns-records`
   - `kustomization.yaml`
2. Wire into the root `kustomization.yaml` alongside the other cluster namespaces.
3. Apply, verify (below), then delete the old CR:
   `kubectl -n wikileet delete dnsendpoint wikileet-prod`
4. In `django-gift-wiki`: delete `deploy/cloudrun/`, drop the
   `kubectl apply -k deploy/cloudrun` note from its `CLAUDE.md`, close issue #21
   pointing here.
5. Once the CR is gone, `wikileet` holds only `pvc/wikileet-db` (pre-Neon SQLite
   volume, `longhorn-retain`) and stale secrets incl. live Neon prod credentials.
   Decide separately whether to keep the PVC; the namespace can then be deleted
   outright, which is the whole point of this plan.

Namespace name `dns-records` is a choice, not a constraint — anything works as
long as it holds records only and never a workload.

## Verification

```bash
# CR present in the new namespace, gone from the old
kubectl get dnsendpoint -A

# external-dns picked it up without error
kubectl -n externaldns logs deploy/external-dns --tail=50 | grep -i giftwiki

# resolution unchanged (expect ghs.googlehosted.com)
dig +short giftwiki.leetserve.com
dig +short giftwiki-dev.leetserve.com

# and the app still answers through it
curl -s -o /dev/null -w '%{http_code}\n' https://giftwiki.leetserve.com/
```

Expect `200`. Note first hit may take ~10s — Cloud Run scales to zero and the
Neon compute now suspends after 5 min idle; both cold-start. Warm is ~150ms.

## Rollback

`upsert-only` means the Route53 record survives any mistake here. To restore the
previous topology:

```bash
kubectl apply -f - <<'EOF'
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: wikileet-prod
  namespace: wikileet
spec:
  endpoints:
  - dnsName: giftwiki.leetserve.com
    recordType: CNAME
    targets: [ghs.googlehosted.com]
    recordTTL: 300
  - dnsName: giftwiki-dev.leetserve.com
    recordType: CNAME
    targets: [ghs.googlehosted.com]
    recordTTL: 300
EOF
```

The `wikileet` namespace must still exist for this to apply. Do not delete that
namespace until this plan is complete and verified.
