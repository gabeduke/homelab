# homelab

Infrastructure as code for home network, Kubernetes cluster, and devices.

## Repository Structure

- **`clusters/`** - Kubernetes cluster definitions (K3s + GitOps)
- **`devices/`** - Non-cluster devices (RetroPie, Home Assistant, etc.)
- **`secrets/`** - Secret files for Kustomize (not tracked in git)
- **`scripts/`** - Cluster provisioning and setup scripts
- **`CLAUDE.md`** - AI assistant guidance for this repository

## Kubernetes Cluster

### Bootstrap

```bash
flux bootstrap git \
  --url=ssh://git@github.com/gabeduke/homelab \
  --branch=main \
  --path=clusters/k3d
```