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
The control plane has taint `node-role.kubernetes.io/master=true:NoSchedule`. System components like node-exporter need tolerations to run on the control plane.

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

## Important Notes

- The `.k3s.yaml` file is the downloaded kubeconfig (not tracked in git)
- Makefile variables `USER`, `CONTROL_PLANE_NODE`, `WORKER*` define the cluster topology
- Some resources in kustomization files are commented out (e.g., `# - namespace-kube-system`)
- The `--server-side --force-conflicts` flags in `make iot` handle CRD ownership conflicts
- Scripts in `scripts/` are synced to nodes via `make sync` before installation
