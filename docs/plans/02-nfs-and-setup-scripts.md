# Plan 02 — NFS module loading, script dedupe, unattended reboot

**Findings:** S6-5, S6-9, S6-10, S6-12
**Risk:** low · **Cluster impact:** none (module loads are idempotent) · **Needs SSH:** yes
**Blocks:** nothing · **Blocked by:** nothing

The headline bug: `modprobe` is called without `sudo`, fails, and the script's
fallback logic reports **success anyway**. So the current state of NFS support on
the nodes is unknown — the tooling has been lying about it.

---

## S6-5 — `modprobe` without `sudo` produces a false success

### The bug

`scripts/setup.sh:114` and `scripts/load-nfs-modules.sh:57`:

```bash
ERROR_MSG=$(modprobe "$module" 2>&1)
```

Every other privileged call in these scripts uses `sudo`. This one does not.
`make setup` connects as `gabeduke`, an unprivileged user, and `modprobe`
requires `CAP_SYS_MODULE`, so it fails with `Operation not permitted`.

The script then enters this branch:

```bash
if echo "$ERROR_MSG" | grep -qi "operation not permitted"; then
    if check_module_loading_restricted; then
        ...
        if check_nfs_available; then
            echo "    ✓ NFS filesystem support is available (built into kernel)"
```

`check_nfs_available` greps `/proc/filesystems` for `nfs`, which is true on any
kernel with NFS **client** support compiled in — regardless of whether the
modules this script was asked to load actually loaded. So a permission failure
is reported as a green check.

Roughly 200 lines of kernel-lockdown and built-in detection exist to
rationalise a missing four-letter word.

### Why it matters

Longhorn RWX volumes need the client stack (`sunrpc`, `lockd`, `nfs`). If those
are genuinely missing on a node, RWX volumes fail to mount there — and the
tooling currently cannot tell you. Establish ground truth first:

```bash
make check-nfs-modules      # existing target, reads lsmod — this one is honest
```

### The fix

Add `sudo`, then delete the heuristics it was covering for. `scripts/load-nfs-modules.sh`
becomes the single implementation (see S6-9), reduced from 195 lines to ~70:

```bash
#!/bin/bash
#
# Load the NFS kernel modules Longhorn needs for RWX volumes, and make them
# persist across reboots. Safe to re-run; safe to run on a node where the
# modules are built into the kernel rather than loadable.
#
# Run directly on a node, or from the repo root via `make load-nfs-modules`.
# `setup.sh` also calls this so the logic lives in exactly one place.

set -uo pipefail

# modprobe needs CAP_SYS_MODULE. We connect as an unprivileged user, so every
# load must go through sudo -- without it modprobe fails with "Operation not
# permitted" and the old version of this script reported a false success.
MODULES="sunrpc lockd nfs nfsd"

# A module compiled into the kernel is reported by modinfo as "(builtin)".
# It is present and working, it just cannot be loaded or unloaded.
is_builtin() {
    [ "$(modinfo -F filename "$1" 2>/dev/null)" = "(builtin)" ]
}

echo "==> Loading NFS kernel modules (Longhorn RWX)"

missing=0
for module in $MODULES; do
    if lsmod | grep -q "^${module} "; then
        echo "    ok    $module (already loaded)"
    elif is_builtin "$module"; then
        echo "    ok    $module (built into kernel)"
    elif sudo modprobe "$module"; then
        echo "    ok    $module (loaded)"
    else
        echo "    WARN  $module could not be loaded"
        missing=$((missing + 1))
    fi
done

# The client side -- sunrpc, lockd, nfs -- is what Longhorn's RWX mounts need.
# nfsd is the server side and only matters if this node runs the share itself.
echo "==> Verifying NFS filesystem support"
if grep -qE '^nodev[[:space:]]+nfs4?$|[[:space:]]nfs4?$' /proc/filesystems; then
    echo "    ok    kernel reports: $(awk '$NF ~ /^nfs4?$/ {printf "%s ", $NF}' /proc/filesystems)"
elif [ "$missing" -eq 0 ]; then
    echo "    ok    all modules present (filesystem list did not report nfs)"
else
    echo "    WARN  NFS filesystem support not detected -- RWX volumes will not work"
fi

# Persist across reboots. Only loadable modules belong here; listing a builtin
# makes systemd-modules-load log a spurious failure on every boot.
MODULES_FILE="/etc/modules-load.d/k3s-nfs.conf"
if [ -f "$MODULES_FILE" ]; then
    echo "==> $MODULES_FILE already present"
else
    echo "==> Writing $MODULES_FILE"
    loadable=""
    for module in $MODULES; do
        is_builtin "$module" || loadable="${loadable}${module}"$'\n'
    done
    if [ -n "$loadable" ]; then
        printf '%s' "$loadable" | sudo tee "$MODULES_FILE" >/dev/null
        echo "    ok    persisted: $(echo "$loadable" | tr '\n' ' ')"
    else
        echo "    ok    all modules are builtin, nothing to persist"
    fi
fi

exit 0
```

Two details worth keeping:

- **`is_builtin` via `modinfo -F filename`** returns the literal string
  `(builtin)` for a compiled-in module. This is a positive check, unlike the old
  code's inference from an error message, and it is what makes the
  `modules-load.d` write correct — listing a builtin there makes
  `systemd-modules-load` log a failure on every boot.
- **`nfsd` is the server side.** Longhorn's RWX mounts need the client stack.
  `nfsd` only matters if the node hosts the share. The script warns rather than
  fails when only `nfsd` is missing.

### Verification

```bash
make sync                       # push the new script
make load-nfs-modules           # should now show real loads, not inferred ones
make check-nfs-modules          # independent confirmation via lsmod
ssh gabeduke@betapi 'cat /etc/modules-load.d/k3s-nfs.conf'
ssh gabeduke@betapi 'sudo systemd-analyze verify systemd-modules-load.service 2>&1 | head'
```

Then reboot **one** worker and confirm the modules come back on their own:

```bash
ssh gabeduke@betapi 'sudo reboot'
# wait, then:
ssh gabeduke@betapi 'lsmod | grep -E "^(nfs|lockd|sunrpc)"'
kubectl get nodes                # betapi back to Ready
```

---

## S6-9 — ~100 duplicated lines between the two scripts

`setup.sh` contains a near-verbatim copy of the whole module-loading block from
`load-nfs-modules.sh`, including both helper functions. Two copies of subtle
logic guarantee divergence; they have already drifted slightly (`setup.sh` adds a
kernel-headers install path the standalone script lacks).

### The fix

`make sync` already copies both scripts to `/home/gabeduke/` on every node, so
`setup.sh` can just call the other:

```bash
# NFS modules for Longhorn RWX. Kept in its own script so `make load-nfs-modules`
# and `make setup` cannot drift apart; both run exactly this code.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/load-nfs-modules.sh" ]; then
    "$SCRIPT_DIR/load-nfs-modules.sh"
else
    echo "WARN: load-nfs-modules.sh not found next to setup.sh -- skipping NFS setup"
    echo "      run 'make sync' from the repo root, then re-run setup"
fi
```

`ssh <node> bash setup.sh` runs with `$0 = setup.sh` and cwd `/home/gabeduke`,
so `dirname` resolves correctly. Delete the duplicated block and both helper
functions from `setup.sh`.

> Keep the `make sync` ordering in mind: `sync` must run before `setup`, which it
> already does in `apply-cluster`. The `else` branch above makes the failure
> legible instead of silent if someone runs `setup` alone on a fresh node.

---

## S6-10 — `scripts/ip.sh` is dead and its name is a trap

```bash
$ cat scripts/ip.sh
hostname --all-ip-addresses | awk '{print $1}'
```

It is never synced anywhere. `make sync` copies **`scripts/control-plane/ip.sh`**
to `/home/gabeduke/ip.sh`, and `make setup-cron` schedules that same path. So the
file that runs hourly on alphapi is the control-plane one; this three-line
top-level script has no caller.

The danger is the shared basename: a future edit to "ip.sh" has even odds of
landing in the file that does nothing.

### The fix

```bash
git rm scripts/ip.sh
```

Its one line already exists inline in `control-plane/run.sh` and in the Makefile's
`CONTROL_IP`. Nothing references it — confirm before deleting:

```bash
grep -rn "scripts/ip.sh\|ip\.sh" Makefile scripts/ docs/ README.md CLAUDE.md
```

Expect hits only for `control-plane/ip.sh`.

---

## S6-12 — `setup.sh` reboots unattended, mid-`apply-cluster`

### The bug

```bash
if [ "$NEEDS_REBOOT" = true ]; then
    echo "Rebooting in 10 seconds... (Ctrl+C to cancel)"
    sleep 10
    sudo reboot
```

`make apply-cluster` runs `sync setup install-control-plane install-agent` in
order, and `make setup` hits all three nodes. If `setup.sh` decides alphapi needs
a reboot, the control plane goes down **with no drain**, and the very next target
(`install-control-plane`) SSHes into a rebooting host. The 10-second `Ctrl+C`
window is also meaningless over a non-interactive `ssh <node> bash setup.sh`.

This is fine on a bare node during first provisioning. It is not fine re-run
against a live cluster — which is exactly what someone does when they think
"I'll just re-run the provisioning scripts."

### The fix

Gate it, and default to off:

```bash
# Rebooting is opt-in: `make setup` also runs against live nodes, where an
# unannounced control-plane reboot means an undrained outage.
REBOOT="${REBOOT:-0}"

if [ "$NEEDS_REBOOT" = true ]; then
    if [ "$REBOOT" = "1" ]; then
        echo "==> Kernel parameters changed; rebooting now (REBOOT=1)."
        sudo reboot
    else
        echo "==> Kernel parameters changed. A REBOOT IS REQUIRED for cgroups to apply."
        echo "    Nothing was rebooted. Re-run with REBOOT=1, or reboot manually:"
        echo "      ssh $(hostname) 'sudo reboot'"
        exit 3      # distinct code so the Makefile can report it
    fi
fi
```

Pass it through from the Makefile as part of the remote command string (`ssh`
does not forward environment variables by default):

```makefile
REBOOT ?= 0

.PHONY: setup
setup:
	@for n in $(ALL_NODES); do \
		echo "==> setup $$n"; \
		ssh $$n "REBOOT=$(REBOOT) bash setup.sh"; \
		rc=$$?; \
		if [ $$rc -eq 3 ]; then echo "!! $$n needs a reboot -- re-run with REBOOT=1"; \
		elif [ $$rc -ne 0 ]; then echo "!! $$n setup failed ($$rc)"; exit $$rc; fi; \
	done
```

Reboot one node at a time when it is needed, never the whole cluster at once,
and drain the control plane first if it is alphapi.

### Verification

```bash
make setup                 # on already-configured nodes: "No changes needed"
make setup REBOOT=1        # only when you have decided a reboot is acceptable
```

---

## Commit

```
Fix false-success NFS module loading; de-duplicate and gate setup scripts

- modprobe ran without sudo, failed with EPERM, and the fallback heuristics
  reported success anyway -- the real NFS state on the nodes was unknown.
  Add sudo and delete the ~120 lines of inference it was covering for.
- setup.sh now calls load-nfs-modules.sh instead of carrying a drifted copy.
- setup.sh no longer reboots unattended; REBOOT=1 opts in, exit 3 signals
  "reboot required". `make apply-cluster` could previously reboot the control
  plane undrained and then SSH into it.
- Delete the unreferenced scripts/ip.sh; the live one is control-plane/ip.sh
  and the shared basename invited edits to the wrong file.
```
