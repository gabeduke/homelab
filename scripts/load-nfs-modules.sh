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

# Snapshot lsmod once and match against the string. Deliberately NOT
# `lsmod | grep -q`: grep -q exits on first match, lsmod takes SIGPIPE, and
# under `set -o pipefail` the pipeline returns 141 -- so an already-loaded
# module was reported as freshly loaded, non-deterministically, depending on
# whether lsmod finished writing before grep exited.
LSMOD="$(lsmod)"
is_loaded() {
    case $'\n'"$LSMOD" in
        *$'\n'"$1 "*) return 0 ;;
    esac
    return 1
}

echo "==> Loading NFS kernel modules (Longhorn RWX)"

# PERSIST collects only modules that are actually loaded AND loadable -- a
# builtin does not belong in modules-load.d, and neither does one that failed:
# either makes systemd-modules-load log a failure on every boot.
missing=0
PERSIST=""
for module in $MODULES; do
    if is_loaded "$module"; then
        echo "    ok    $module (already loaded)"
        PERSIST="${PERSIST}${module} "
    elif is_builtin "$module"; then
        echo "    ok    $module (built into kernel)"
    elif sudo modprobe "$module"; then
        echo "    ok    $module (loaded)"
        PERSIST="${PERSIST}${module} "
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
    if [ -n "$PERSIST" ]; then
        printf '%s\n' $PERSIST | sudo tee "$MODULES_FILE" >/dev/null
        echo "    ok    persisted: $PERSIST"
    else
        echo "    ok    nothing loadable to persist (all builtin or unavailable)"
    fi
fi

exit 0
