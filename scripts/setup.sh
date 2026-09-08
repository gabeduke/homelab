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

# Load NFS kernel modules required for Longhorn RWX volumes
# Required modules: nfs, nfsd, lockd, sunrpc
# Note: On Raspberry Pi, some modules may be built into the kernel
echo "Loading NFS kernel modules for Longhorn RWX support..."
set +e  # Temporarily disable exit on error for module loading
KERNEL_VERSION=$(uname -r)

# Check if NFS is available in the kernel (built-in or module)
check_nfs_available() {
    # Check if NFS filesystem is supported (this is the most reliable check)
    if grep -q " nfs " /proc/filesystems 2>/dev/null; then
        return 0
    fi
    # Check if NFSv4 filesystem is supported
    if grep -q " nfs4 " /proc/filesystems 2>/dev/null; then
        return 0
    fi
    # Check if NFS modules exist
    if find /lib/modules/"$KERNEL_VERSION" -name "nfs.ko*" -o -name "nfsd.ko*" 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

# Check if kernel module loading is restricted
check_module_loading_restricted() {
    # Check for kernel lockdown mode
    if [ -f /sys/kernel/security/lockdown ] && grep -q "\[none\]" /sys/kernel/security/lockdown 2>/dev/null; then
        return 1  # Not restricted
    elif [ -f /sys/kernel/security/lockdown ] && grep -q "\[integrity\]\|\[confidentiality\]" /sys/kernel/security/lockdown 2>/dev/null; then
        return 0  # Restricted
    fi
    # Check if secure boot is enabled (might restrict module loading)
    if [ -d /sys/firmware/efi ] && [ -f /sys/firmware/efi/efivars/SecureBoot-* ] 2>/dev/null; then
        # Secure boot might be enabled, but doesn't always restrict modules
        return 1
    fi
    return 1  # Assume not restricted if we can't determine
}

# Load modules in dependency order: sunrpc -> lockd -> nfs -> nfsd
MODULES="sunrpc lockd nfs nfsd"
LOADED_COUNT=0
BUILTIN_COUNT=0

for module in $MODULES; do
    if lsmod | grep -q "^${module}"; then
        echo "  ✓ $module is already loaded"
        LOADED_COUNT=$((LOADED_COUNT + 1))
    else
        echo "  → Loading $module..."
        # Capture actual error message
        ERROR_MSG=$(modprobe "$module" 2>&1)
        if [ $? -eq 0 ]; then
            echo "  ✓ $module loaded successfully"
            LOADED_COUNT=$((LOADED_COUNT + 1))
        else
            # Check if module is built into kernel (modprobe returns specific error)
            if echo "$ERROR_MSG" | grep -qi "built-in\|builtin"; then
                echo "  ✓ $module is built into kernel (not a loadable module)"
                BUILTIN_COUNT=$((BUILTIN_COUNT + 1))
            elif [ ! -d "/lib/modules/$KERNEL_VERSION" ] || [ ! -f "/lib/modules/$KERNEL_VERSION/modules.dep" ]; then
                echo "  ⚠ Failed to load $module: kernel modules directory missing"
                echo "    Installing kernel headers for $KERNEL_VERSION..."
                sudo apt-get -o DPkg::Lock::Timeout=60 update || echo "Warning: apt-get update failed"
                sudo apt-get -o DPkg::Lock::Timeout=60 install -y "linux-headers-${KERNEL_VERSION}" || echo "Warning: kernel headers installation failed"
                # Try loading again
                if modprobe "$module" 2>/dev/null; then
                    echo "  ✓ $module loaded after installing headers"
                    LOADED_COUNT=$((LOADED_COUNT + 1))
                else
                    echo "  ⚠ $module: $(echo "$ERROR_MSG" | head -1)"
                fi
            else
                # Check for "Operation not permitted" - might be kernel lockdown or security policy
                if echo "$ERROR_MSG" | grep -qi "operation not permitted"; then
                    if check_module_loading_restricted; then
                        echo "  ⚠ $module: kernel module loading is restricted (kernel lockdown or security policy)"
                        echo "    Checking if NFS support is available via built-in kernel..."
                        if check_nfs_available; then
                            echo "    ✓ NFS filesystem support is available (built into kernel)"
                            BUILTIN_COUNT=$((BUILTIN_COUNT + 1))
                        else
                            echo "    ⚠ NFS support may not be available"
                        fi
                    elif check_nfs_available; then
                        echo "  ✓ $module: NFS support available (built into kernel, module loading restricted)"
                        BUILTIN_COUNT=$((BUILTIN_COUNT + 1))
                    else
                        echo "  ⚠ $module: Operation not permitted - may need to check kernel configuration"
                    fi
                elif check_nfs_available; then
                    echo "  ✓ $module: NFS support available (built into kernel)"
                    BUILTIN_COUNT=$((BUILTIN_COUNT + 1))
                else
                    echo "  ⚠ $module: $(echo "$ERROR_MSG" | head -1)"
                fi
            fi
        fi
    fi
done
set -e  # Re-enable exit on error

# Make NFS modules persistent across reboots (only if they're loadable modules)
MODULES_FILE="/etc/modules-load.d/k3s-nfs.conf"
if [ ! -f "$MODULES_FILE" ]; then
    echo "Making NFS modules persistent across reboots..."
    for module in $MODULES; do
        # Only add to modules-load.d if the module can be loaded (not built-in)
        if modprobe -n "$module" 2>/dev/null; then
            echo "$module" | sudo tee -a "$MODULES_FILE" > /dev/null
        fi
    done
    if [ -f "$MODULES_FILE" ]; then
        echo "  ✓ Created $MODULES_FILE"
    else
        echo "  ℹ All NFS modules appear to be built into kernel (no modules-load.d file needed)"
    fi
else
    echo "  ✓ NFS modules already configured to load on boot"
fi

# Verify NFS support is available
TOTAL_NFS_SUPPORT=$((LOADED_COUNT + BUILTIN_COUNT))
NFS_FS_AVAILABLE=false
NFS_VERSIONS=""
if check_nfs_available; then
    NFS_FS_AVAILABLE=true
    # Check which NFS versions are available
    if grep -q " nfs " /proc/filesystems 2>/dev/null; then
        NFS_VERSIONS="${NFS_VERSIONS}nfs "
    fi
    if grep -q " nfs4 " /proc/filesystems 2>/dev/null; then
        NFS_VERSIONS="${NFS_VERSIONS}nfs4 "
    fi
    echo "  ✓ NFS filesystem support detected in kernel (${NFS_VERSIONS})"
fi

# For Longhorn RWX, we primarily need NFS client support (nfs, lockd, sunrpc)
# nfsd (server) is optional unless Longhorn is running its own NFS server
if [ "$NFS_FS_AVAILABLE" = true ]; then
    if [ "$LOADED_COUNT" -ge 3 ] || [ "$TOTAL_NFS_SUPPORT" -ge 3 ]; then
        echo "  ✓ NFS support sufficient for Longhorn RWX ($LOADED_COUNT loaded, $BUILTIN_COUNT built-in)"
    else
        echo "  ✓ NFS filesystem support available (may work for RWX: $LOADED_COUNT loaded, $BUILTIN_COUNT built-in)"
    fi
elif [ "$TOTAL_NFS_SUPPORT" -ge 2 ]; then
    echo "  ✓ NFS support available ($LOADED_COUNT loaded, $BUILTIN_COUNT built-in)"
else
    echo "  ⚠ Warning: Limited NFS support ($LOADED_COUNT loaded, $BUILTIN_COUNT built-in)"
    echo "    NFS filesystem not detected - RWX volumes may not work"
    echo "    Consider: checking kernel configuration or installing kernel modules"
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

# Only reboot if changes were made
if [ "$NEEDS_REBOOT" = true ]; then
    echo "Kernel parameters updated. Reboot required for changes to take effect."
    echo "Rebooting in 10 seconds... (Ctrl+C to cancel)"
    sleep 10
    sudo reboot
else
    echo "No changes needed. System is already configured correctly."
fi
