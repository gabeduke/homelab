# Plan 01 — Makefile correctness + stale docs

**Findings:** S6-2, S6-6, S6-7, S6-11, S6-13
**Risk:** low · **Cluster impact:** none · **Needs SSH:** no (to edit); yes (to verify S6-2)
**Blocks:** nothing · **Blocked by:** nothing

Four independent bugs in `Makefile`, plus one stale statement in `CLAUDE.md`.
None of these change cluster state. This is the safest place to start.

---

## S6-2 — `make patch` upgrades nothing on the Pis

### The bug

```makefile
patch-agent1:
	ssh $(WORKER1) sudo apt-get update && sudo apt-get upgrade -y
```

Make runs each recipe line via `/bin/sh -c`. The `&&` is parsed by that **local**
shell, not by the remote one. So `apt-get update` runs on the Pi and
`apt-get upgrade -y` runs on the Mac, where there is no `apt-get`. Every
`patch-*` target has this shape, which means **no node has ever been upgraded by
`make patch`** — it has only ever refreshed remote package indexes.

This matters more than it looks: see plan 06, where both workers are on an
Ubuntu release that went EOL two months ago.

### The fix

Quote the whole remote command so `&&` is sent to the remote shell:

```makefile
patch-control-plane:
	ssh $(CONTROL_PLANE_NODE) 'sudo apt-get update && sudo apt-get upgrade -y'
```

Apply to all four `patch-*` targets. Note this combines with S6-11 below — once
there is a `WORKERS` list, the three near-identical agent targets collapse into one.

### Verification

```bash
# Before: prints the Mac's uname. After: prints the Pi's.
ssh gabeduke@betapi 'uname -a && apt list --upgradable 2>/dev/null | head'
make patch
ssh gabeduke@betapi 'apt list --upgradable 2>/dev/null | wc -l'   # should drop
```

---

## S6-6 — `make merge-kubeconfig` is a silent no-op

### The bug

```makefile
kubeconfig=~/.kube/config:.k3s.yaml kubectl config view --flatten > /tmp/config
```

The variable is lowercase. kubectl reads **`KUBECONFIG`**. As written this sets an
unrelated shell variable, kubectl falls back to the default `~/.kube/config`,
`--flatten` dumps that file, and the next line overwrites `~/.kube/config` with
itself. The merge has never happened. The `config.bak` line is the only reason
this has been harmless.

### The fix

```makefile
.PHONY: merge-kubeconfig
merge-kubeconfig: get-kubeconfig
	cp ~/.kube/config ~/.kube/config.bak
	KUBECONFIG=$$HOME/.kube/config:$(PWD)/.k3s.yaml kubectl config view --flatten > /tmp/config
	mv /tmp/config ~/.kube/config
```

Three changes beyond the case fix:
- `$$HOME` rather than `~` — `~` does not expand inside an assignment prefix in `sh`.
- `$(PWD)/.k3s.yaml` — absolute, so the target is not cwd-dependent.
- depend on `get-kubeconfig` so it cannot merge a stale or missing file.

### Verification

```bash
make merge-kubeconfig
kubectl config get-contexts        # the k3s context should be present
diff <(kubectl config view) <(cat ~/.kube/config.bak)   # must NOT be empty
```

---

## S6-7 — `make get-kubeconfig` produces an unusable file

### Two bugs

```makefile
@scp $(CONTROL_PLANE_NODE):/etc/rancher/k3s/k3s.yaml .k3s.yaml
chown $(USER):$(USER) .k3s.yaml
```

1. `chown gabeduke:gabeduke` — there is no `gabeduke` **group** on macOS (it is
   `staff`), so this fails. It is also pointless: `scp` already writes the file
   as the invoking user.
2. The fetched file has `server: https://127.0.0.1:6443`, which only works when
   run on alphapi itself.

### The fix

```makefile
.PHONY: get-kubeconfig
get-kubeconfig:
	@scp $(CONTROL_PLANE_NODE):/etc/rancher/k3s/k3s.yaml .k3s.yaml
	@chmod 600 .k3s.yaml
	@sed -i.bak 's|https://127.0.0.1:6443|https://$(CONTROL_IP):6443|' .k3s.yaml && rm -f .k3s.yaml.bak
	@echo "==> .k3s.yaml points at $(CONTROL_IP):6443"
```

`chmod 600` replaces the `chown` — the file holds cluster admin credentials and
`scp` does not guarantee restrictive permissions. `sed -i.bak` is the BSD/macOS
form; plain `sed -i` fails there.

> **Check before relying on this:** the rewritten host must be in the API server
> cert SANs. `CONTROL_IP` (192.168.1.84) is passed as a SAN by `run.sh`, so this
> works on-network today. Plan 03 makes that guarantee explicit and durable.

### Verification

```bash
make get-kubeconfig
KUBECONFIG=.k3s.yaml kubectl get nodes    # must succeed from the Mac
ls -l .k3s.yaml                           # -rw------- 
grep -c 127.0.0.1 .k3s.yaml               # 0
```

---

## S6-11 — node lists are hand-copied across six targets

### The problem

`sync`, `setup`, `install-agent`, `uninstall`, `patch`, and `load-nfs-modules`
each maintain their own copy of the worker list, each with its own
commented-out `mothership` / `bigpi` lines. Adding or removing a node is a
six-place edit, and the copies have already drifted — `patch-agent4` exists but
is not referenced by `make patch`, and `WORKER3`/`WORKER4` are defined but
commented out everywhere they are used.

Neither `mothership` nor `bigpi` is in the cluster:

```
$ kubectl get nodes
alphapi  betapi  charliepi
```

### The fix

Replace the numbered variables with a list, and generate the per-node targets:

```makefile
CONTROL_PLANE_NODE = $(USER)@alphapi
# Workers currently in the cluster. mothership and bigpi were removed; add them
# back here (and nowhere else) to bring them in.
WORKER_HOSTS = betapi charliepi
WORKERS      = $(addprefix $(USER)@,$(WORKER_HOSTS))
ALL_NODES    = $(CONTROL_PLANE_NODE) $(WORKERS)
```

Then each target iterates instead of repeating. Use a `for` loop in a single
recipe line so a failure on one node is visible rather than silently skipped:

```makefile
.PHONY: patch
patch:
	@for n in $(ALL_NODES); do \
		echo "==> patching $$n"; \
		ssh $$n 'sudo apt-get update && sudo apt-get upgrade -y' || echo "!! $$n FAILED"; \
	done

.PHONY: sync
sync:
	scp scripts/control-plane/run.sh scripts/control-plane/ip.sh scripts/setup.sh \
		scripts/load-nfs-modules.sh $(CONTROL_PLANE_NODE):/home/$(USER)/
	@for n in $(WORKERS); do \
		scp scripts/agent/run.sh scripts/setup.sh scripts/load-nfs-modules.sh $$n:/home/$(USER)/ || exit 1; \
	done
```

Do the same for `setup`, `install-agent`, `uninstall`, and `load-nfs-modules`.
Delete `WORKER1`–`WORKER4` and the `patch-agent1/2/4`, `load-nfs-agent1/2` targets.

> `make patch` previously used `$(MAKE) -j` for parallelism. The loop above is
> serial. That is deliberate — parallel `apt-get upgrade` across nodes interleaves
> output unreadably, and these are three Raspberry Pis, not a fleet. If you want
> the parallelism back, keep `-j` but note it must not be used for `make iot`
> (the existing comment there explains why).

### Verification

```bash
make -n sync patch setup          # dry-run: inspect the expanded commands
make sync                         # real run; all three nodes should be touched
```

---

## S6-13 — `CLAUDE.md` documents the wrong taint

`CLAUDE.md` states:

> The control plane has taint `node-role.kubernetes.io/master=true:NoSchedule`.

The live taint is `control-plane`, and has been since session 1 fixed exactly
this mismatch (it was the cause of the off-network access outage — `svclb-traefik`
tolerates `control-plane`, so with the `master` key it never scheduled):

```
$ kubectl get node alphapi -o jsonpath='{.spec.taints}'
[{"effect":"NoSchedule","key":"node-role.kubernetes.io/control-plane","value":"true"}]
```

`scripts/control-plane/run.sh` also uses `control-plane`. Only the doc is stale.

### The fix

Update the sentence in `CLAUDE.md` to name `node-role.kubernetes.io/control-plane`,
and add a line noting that the deprecated `master` key is intentionally still
listed alongside it in `namespace-longhorn-system/patch-*-tolerations.yaml:10`
(harmless, both keys are tolerated — this is already item 6 in the carried-over
next steps).

---

## Commit

One commit per finding, or one commit for the Makefile and one for the doc.
Suggested message:

```
Fix four Makefile bugs: remote patching, kubeconfig merge, kubeconfig fetch, node lists

- patch-*: quote the remote command so `&&` runs on the node, not the Mac.
  No node had ever actually been upgraded by `make patch`.
- merge-kubeconfig: KUBECONFIG was lowercase, so the merge was a no-op that
  overwrote ~/.kube/config with itself.
- get-kubeconfig: drop the failing macOS chown, chmod 600 instead, and rewrite
  the 127.0.0.1 server address so the file works off-node.
- Replace WORKER1..4 with a single WORKERS list; six targets had hand-copied
  node lists that had already drifted.
```
