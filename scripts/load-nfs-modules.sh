#!/bin/bash

# Script to load NFS kernel modules required for Longhorn RWX volumes
# This should be run on each k3s node
# Note: On Raspberry Pi, some modules may be built into the kernel

set +e  # Don't exit on error for module loading

echo "========================================="
echo "Loading NFS Kernel Modules for RWX"
echo "========================================="
echo ""

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
    return 1  # Assume not restricted if we can't determine
}

# Load modules in dependency order: sunrpc -> lockd -> nfs -> nfsd
MODULES=("sunrpc" "lockd" "nfs" "nfsd")
LOADED_COUNT=0
BUILTIN_COUNT=0

for module in "${MODULES[@]}"; do
    echo "Checking module: $module"
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
            # Check if module is built into kernel
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

echo ""
echo "Verifying NFS support:"
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
    echo "✓ NFS filesystem support detected in kernel (${NFS_VERSIONS})"
fi

# For Longhorn RWX, we primarily need NFS client support (nfs, lockd, sunrpc)
if [ "$NFS_FS_AVAILABLE" = true ]; then
    if [ "$LOADED_COUNT" -ge 3 ] || [ "$TOTAL_NFS_SUPPORT" -ge 3 ]; then
        echo "✓ NFS support sufficient for Longhorn RWX ($LOADED_COUNT loaded, $BUILTIN_COUNT built-in)"
    else
        echo "✓ NFS filesystem support available (may work for RWX: $LOADED_COUNT loaded, $BUILTIN_COUNT built-in)"
    fi
    lsmod | grep -E "^nfs|^nfsd|^lockd|^sunrpc" | sed 's/^/  /' || echo "  (Some modules are built into kernel)"
elif [ "$TOTAL_NFS_SUPPORT" -ge 2 ]; then
    echo "✓ NFS support available ($LOADED_COUNT loaded, $BUILTIN_COUNT built-in)"
    lsmod | grep -E "^nfs|^nfsd|^lockd|^sunrpc" | sed 's/^/  /' || echo "  (Some modules are built into kernel)"
else
    echo "⚠ Warning: Limited NFS support ($LOADED_COUNT loaded, $BUILTIN_COUNT built-in)"
    echo "  NFS filesystem not detected - RWX volumes may not work"
    lsmod | grep -E "^nfs|^nfsd|^lockd|^sunrpc" | sed 's/^/  /' || echo "  No NFS modules found"
fi

# Make modules persistent (only if they're loadable modules)
MODULES_FILE="/etc/modules-load.d/k3s-nfs.conf"
if [ ! -f "$MODULES_FILE" ]; then
    echo ""
    echo "Making modules persistent across reboots..."
    for module in "${MODULES[@]}"; do
        # Only add to modules-load.d if the module can be loaded (not built-in)
        if modprobe -n "$module" 2>/dev/null; then
            echo "$module" | sudo tee -a "$MODULES_FILE" > /dev/null
        fi
    done
    if [ -f "$MODULES_FILE" ]; then
        echo "✓ Created $MODULES_FILE"
    else
        echo "ℹ All NFS modules appear to be built into kernel (no modules-load.d file needed)"
    fi
else
    echo ""
    echo "✓ Modules already configured to load on boot ($MODULES_FILE exists)"
fi

echo ""
echo "========================================="
echo "NFS Module Setup Complete"
echo "========================================="

set -e  # Re-enable exit on error












