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

# Only reboot if changes were made
if [ "$NEEDS_REBOOT" = true ]; then
    echo "Kernel parameters updated. Reboot required for changes to take effect."
    echo "Rebooting in 10 seconds... (Ctrl+C to cancel)"
    sleep 10
    sudo reboot
else
    echo "No changes needed. System is already configured correctly."
fi
