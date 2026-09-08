#!/bin/bash

set -e

# Detect cmdline.txt location (Ubuntu uses /boot/firmware/current/cmdline.txt, Raspberry Pi OS uses /boot/firmware/cmdline.txt or /boot/cmdline.txt)
if [ -f /boot/firmware/current/cmdline.txt ]; then
    CMDLINE_FILE="/boot/firmware/current/cmdline.txt"
elif [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [ -f /boot/cmdline.txt ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
else
    echo "Error: Could not find cmdline.txt file"
    exit 1
fi

# Check current running kernel parameters (from /proc/cmdline) and the boot file
CURRENT_CMDLINE=$(cat /proc/cmdline)
CGROUPS_ENABLED=$(grep -o 'cgroup_memory=1' "$CMDLINE_FILE" 2>/dev/null || echo "$CURRENT_CMDLINE" | grep -o 'cgroup_memory=1' || true)
CGROUP_DISABLE_MEMORY=$(grep -o 'cgroup_disable=memory' "$CMDLINE_FILE" 2>/dev/null || echo "$CURRENT_CMDLINE" | grep -o 'cgroup_disable=memory' || true)
NEEDS_REBOOT=false

# Install Raspberry Pi kernel modules if available and not already installed
# On newer Ubuntu versions, modules may be version-specific and already installed
set +e  # Temporarily disable exit on error for this command
if dpkg -l | grep -q "linux-modules.*raspi"; then
    echo "Raspberry Pi kernel modules already installed."
elif apt-cache show linux-modules-extra-raspi >/dev/null 2>&1; then
    sudo apt-get -o DPkg::Lock::Timeout=60 install linux-modules-extra-raspi -y || echo "Warning: apt-get install failed. Continuing..."
else
    echo "Note: linux-modules-extra-raspi not available (may use version-specific packages). Continuing..."
fi
set -e  # Re-enable exit on error

# Install Longhorn prerequisites
# Required packages: open-iscsi (for iSCSI support), nfs-common (for RWX volumes)
echo "Installing Longhorn prerequisites..."
set +e  # Temporarily disable exit on error for package installation
if ! dpkg -l | grep -q "^ii.*open-iscsi"; then
    echo "Installing open-iscsi..."
    sudo apt-get -o DPkg::Lock::Timeout=60 update || echo "Warning: apt-get update failed. Continuing..."
    sudo apt-get -o DPkg::Lock::Timeout=60 install open-iscsi -y || echo "Warning: open-iscsi installation failed. Continuing..."
fi

if ! dpkg -l | grep -q "^ii.*nfs-common"; then
    echo "Installing nfs-common..."
    sudo apt-get -o DPkg::Lock::Timeout=60 install nfs-common -y || echo "Warning: nfs-common installation failed. Continuing..."
fi
set -e  # Re-enable exit on error

# Ensure iscsid service is enabled and running
# iscsid is required for Longhorn to provide persistent volumes
if systemctl is-enabled iscsid >/dev/null 2>&1; then
    echo "iscsid service is already enabled."
else
    echo "Enabling iscsid service..."
    sudo systemctl enable iscsid || echo "Warning: Failed to enable iscsid. Continuing..."
fi

if systemctl is-active iscsid >/dev/null 2>&1; then
    echo "iscsid service is already running."
else
    echo "Starting iscsid service..."
    sudo systemctl start iscsid || echo "Warning: Failed to start iscsid. Continuing..."
fi

# NFS modules for Longhorn RWX. Kept in its own script so `make load-nfs-modules`
# and `make setup` cannot drift apart -- both run exactly this code. This block
# used to be a copy of that script which had already diverged from it.
# Invoked via `bash` rather than executed: scp does not reliably carry the
# executable bit, and this script is delivered by `make sync`.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/load-nfs-modules.sh" ]; then
    bash "$SCRIPT_DIR/load-nfs-modules.sh"
else
    echo "WARN: load-nfs-modules.sh not found next to setup.sh -- skipping NFS setup"
    echo "      run 'make sync' from the repo root, then re-run setup"
fi

# Remove conflicting cgroup_disable=memory if present in the file
if grep -q 'cgroup_disable=memory' "$CMDLINE_FILE" 2>/dev/null; then
    echo "Removing cgroup_disable=memory from $CMDLINE_FILE (conflicts with k3s)"
    sudo sed -i 's/ cgroup_disable=memory//g' "$CMDLINE_FILE"
    NEEDS_REBOOT=true
fi

# Add cgroup v2 support if not already present
if [ -z "$CGROUPS_ENABLED" ]; then
    echo "Enabling cgroups in $CMDLINE_FILE"
    # Read current content and append cgroup parameters
    CURRENT_CONTENT=$(sudo cat "$CMDLINE_FILE")
    echo "$CURRENT_CONTENT cgroup_memory=1 cgroup_enable=memory systemd.unified_cgroup_hierarchy=1" | sudo tee "$CMDLINE_FILE" > /dev/null
    NEEDS_REBOOT=true
fi

# Rebooting is opt-in. `make setup` also runs against live nodes, where an
# unannounced control-plane reboot is an undrained outage -- and the 10-second
# "Ctrl+C to cancel" window this used to print is meaningless over a
# non-interactive `ssh <node> bash setup.sh`. Exit 3 signals "reboot required"
# so the Makefile can report it per node.
if [ "$NEEDS_REBOOT" = true ]; then
    if [ "${REBOOT:-0}" = "1" ]; then
        echo "==> Kernel parameters updated; rebooting now (REBOOT=1)."
        sudo reboot
    else
        echo "==> Kernel parameters updated. A REBOOT IS REQUIRED for cgroups to apply."
        echo "    Nothing was rebooted. Re-run with REBOOT=1, or reboot manually:"
        echo "      ssh $(hostname) 'sudo reboot'"
        exit 3
    fi
else
    echo "No changes needed. System is already configured correctly."
fi
