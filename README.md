# homelab

cluster definitions

## Bootstrap

```bash
flux bootstrap git \
  --url=ssh://git@github.com/gabeduke/homelab \
  --branch=main \
  --path=clusters/k3d
```