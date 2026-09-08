# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Kubernetes homelab infrastructure repository managing a Raspberry Pi-based K3s cluster. The infrastructure uses:
- **K3s**: Lightweight Kubernetes distribution for the cluster
- **ArgoCD**: GitOps continuous delivery for application deployments
- **Kustomize**: Template-free Kubernetes manifest management
- **Flux**: Alternative GitOps approach (referenced in README)

## Cluster Architecture

### Physical Infrastructure
The cluster consists of multiple Raspberry Pi nodes defined in the Makefile:
- **Control Plane**: `alphapi` (tagged with NoSchedule taint)
- **Worker Nodes**: `betapi`, `charliepi`, `mothership`, `bigpi`
- Node provisioning scripts are in `scripts/control-plane/` and `scripts/agent/`

### GitOps Structure
```
clusters/
└── iot/                              # Main cluster definition
    ├── kustomization.yaml            # Root kustomization
    ├── namespace-argocd/             # ArgoCD apps (ArgoCD Application CRDs)
    ├── namespace-cert-manager/       # Certificate issuers
    ├── namespace-kube-system/        # Core system components
    ├── namespace-longhorn-system/    # Storage layer
    ├── namespace-minecraft/          # Application workloads
    ├── namespace-monitoring/         # Prometheus/Grafana stack
    └── namespace-system-upgrade/     # K3s upgrade automation
```

Each namespace directory contains Kubernetes manifests that get deployed via Kustomize. The `namespace-argocd/` directory contains ArgoCD Application CRDs that reference external Helm charts or repositories.

### Secret Management
Secrets are managed via Kustomize `secretGenerator` in the root `kustomization.yaml`. Secret source files live in the `secrets/` directory (not tracked in git). When applying secrets, use `kubectl kustomize | kubectl apply -f -` from the repository root.

## Common Commands

### Cluster Lifecycle

**Apply full cluster configuration:**
```bash
make iot
```
This creates namespaces, applies secrets, and deploys all manifests from `clusters/iot/`.

**Bootstrap with Flux (alternative):**
```bash
flux bootstrap git \
  --url=ssh://git@github.com/gabeduke/homelab \
  --branch=main \
  --path=clusters/k3d
```

**Install K3s cluster from scratch:**
```bash
make setup              # Prepare nodes (enable cgroups, install kernel modules)
make apply-cluster      # Sync scripts and install K3s on control plane + agents
```

**Get kubeconfig:**
```bash
make get-kubeconfig     # Downloads to .k3s.yaml
make merge-kubeconfig   # Merges into ~/.kube/config
```

**Uninstall K3s:**
```bash
make uninstall
```

**Patch all nodes:**
```bash
make patch              # Runs apt-get update && upgrade on all nodes in parallel
```

### Application Management

**Apply secrets:**
```bash
make secrets
# Or directly:
kubectl kustomize | kubectl apply -f -
```

**Create namespaces:**
```bash
make namespaces
```

**Access ArgoCD UI:**
```bash
make argocd
# Opens port-forward to localhost:8080 and displays admin password
```

### Development Workflow

When adding new applications:
1. Create ArgoCD Application CRD in `clusters/iot/namespace-argocd/<app-name>.yaml`
2. Add the resource to `clusters/iot/namespace-argocd/kustomization.yaml`
3. If the app needs a namespace-specific configuration, create `clusters/iot/namespace-<name>/` directory
4. Add namespace directory to `clusters/iot/kustomization.yaml` resources list
5. Create secrets in `secrets/` directory and add to root `kustomization.yaml` secretGenerator
6. Apply with `make iot`

When modifying existing manifests:
- Edit files in the appropriate `namespace-*` directory
- Apply changes with `make iot` or `kubectl apply -k clusters/iot`
- ArgoCD applications with `syncPolicy.automated` will self-heal and auto-sync

### Testing Changes

Apply specific namespace:
```bash
kubectl apply -k clusters/iot/namespace-<name>
```

Dry-run to see what would be applied:
```bash
kubectl apply -k clusters/iot --dry-run=client
```

View rendered manifests:
```bash
kubectl kustomize clusters/iot
```

## Key Technologies and Patterns

### ArgoCD Applications
Applications in `namespace-argocd/` follow this pattern:
- Reference external Helm charts or Git repositories
- Define destination namespace and server
- Configure `syncPolicy.automated` for GitOps auto-sync
- Use `helm.values` for inline value overrides

### Tolerations
The control plane has taint `node-role.kubernetes.io/control-plane=true:NoSchedule`
(set by `scripts/control-plane/run.sh`). System components like node-exporter need
tolerations to run on the control plane.

The deprecated `node-role.kubernetes.io/master` key is **not** the live taint.
Documenting it as such caused the session-1 off-network outage: `svclb-traefik`
tolerates `control-plane`, so it never scheduled on alphapi. Some manifests
(`namespace-longhorn-system/patch-manager-tolerations.yaml:10`,
`patch-ui-tolerations.yaml:10`) still list `master` alongside `control-plane` --
harmless, since both keys are tolerated, but do not copy that pattern into new
manifests.

**Anything pinned to alphapi by nodeAffinity needs this toleration explicitly.**
The `k3s-server` upgrade Plan sat `Pending` forever without it -- the
system-upgrade-controller adds a toleration only for the cordon it sets itself
(`node.kubernetes.io/unschedulable`), not for the control-plane taint. See
`docs/plans/05-k3s-136-upgrade.md` *Outcome*, Correction 1.

**Draining a node here needs two PDBs cleared first**, or the eviction retries
until the job's deadline kills it. `drain.force` and `skipWaitForDeleteTimeout`
do **not** defeat a PDB. `influxdb-influxdb2` is a single-replica StatefulSet
with `minAvailable: 1`, so its pod can never be evicted (it uses `emptyDir`, so
`kubectl delete pod` is safe); and Longhorn refuses to release a node's
instance-manager while it holds a volume's last replica -- detaching the volume
is not enough. Full detail and the fixes are in plan 05's *Outcome*.

### External DNS
Services use annotation `external-dns.alpha.kubernetes.io/hostname: <domain>` to automatically create DNS records (domain: leetserve.com).

### Certificate Management
Uses cert-manager with Let's Encrypt for TLS certificates. Cluster issuers are defined in `namespace-cert-manager/`. Ingresses reference `cert-manager.io/cluster-issuer: letsencrypt-prod`.

### Monitoring Stack
Prometheus/Grafana stack deployed via `prom-stack` ArgoCD app:
- Prometheus for metrics collection
- Grafana for visualization (domain: grafana.leetserve.com)
- Custom dashboards via Grafana sidecar
- Credentials stored in `grafana-credentials` secret
- Prometheus Operator CRDs in `namespace-monitoring/`

## Gotchas that have already caused outages

Each of these cost real downtime. They are not hypothetical.

- **`make iot` has a review gate.** `make diff` → `make approve` → apply. It was
  added after a blind apply would have silently upgraded ArgoCD and dropped 11
  people from the forward-auth whitelist. `make apply-iot` bypasses the gate.
  Do not use `make -j` with it — the gate must run before anything mutates.
- **ArgoCD Helm values are not schema-checked before apply.** A bare
  `persistence.enabled: true` in the k8s-at-home common chart (where
  `persistence` is a *map of named volumes*) broke mosquitto rendering for a
  **year**. `selfHeal` could not recover it, because the app could not render
  at all. Render locally first: `helm template <app> ./<chart> -f values.yaml`.
- **`longhorn` must stay the sole default StorageClass.** Two defaults were
  fixed by disabling k3s local-storage at the k3s level. A `kubectl patch` does
  **not** hold: `local-path` is owned by the k3s addon controller from a bundled
  manifest re-applied on upgrade, and `longhorn`'s class is owned by
  longhorn-manager from a ConfigMap. **Re-verify with `kubectl get sc` after any
  k3s upgrade.**
- **Never give a Makefile variable the same name as a tool's environment
  variable.** The Makefile once defined `KUBECONFIG = $(shell ssh ... cat
  k3s.yaml)`. When a variable of that name is in make's environment at startup,
  make re-exports *its* value into every recipe — which would have pointed every
  `kubectl` call in the file at the literal text of `k3s.yaml`.
- **Quote remote commands in `ssh` recipes.** Make runs each recipe line through
  a *local* `/bin/sh`, so in `ssh $(NODE) cmd-a && cmd-b` the `&&` is parsed
  locally and `cmd-b` runs on the workstation. This is why `make patch` refreshed
  package indexes for years without ever upgrading a node.

## Important Notes

- The `.k3s.yaml` file is the downloaded kubeconfig — gitignored; it holds
  cluster admin credentials and `make get-kubeconfig` writes it `chmod 600`
- `STATE.md` is the session handoff scratchpad and is **deliberately untracked**.
  Anything durable belongs in this file or `docs/`, not there
- Makefile node topology is `CONTROL_PLANE_NODE` plus the `WORKER_HOSTS` list;
  add or remove a node there and nowhere else — every target iterates it
- Some resources in kustomization files are commented out (e.g., `# - namespace-kube-system`)
- The `--server-side --force-conflicts` flags in `make iot` handle CRD ownership conflicts
- Scripts in `scripts/` are synced to nodes via `make sync` before installation
- `docs/plans/` holds self-contained implementation plans (context, exact diffs,
  verification, rollback) with the dependency order in its README
