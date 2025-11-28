#!/bin/bash
# Fix nested navigation issues (e.g., having to go into a subfolder to see games)
# This commonly happens when ROMs are uploaded inside a subdirectory

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <system> [--dry-run]"
    echo ""
    echo "Fix nested directory issues in ROM folders"
    echo ""
    echo "This happens when ROMs are accidentally uploaded into a subdirectory"
    echo "instead of directly in the system's ROM folder."
    echo ""
    echo "Available systems:"
    echo "  nes snes n64 gb gbc gba genesis mastersystem gamegear atari2600 psx arcade"
    echo ""
    echo "Options:"
    echo "  --dry-run      Show what would be fixed without making changes"
    echo ""
    echo "Examples:"
    echo "  $0 snes --dry-run      # Check for nested directories"
    echo "  $0 snes                # Fix nested directories"
    echo "  $0 all                 # Fix all systems"
    exit 1
fi

SYSTEM="$1"
DRY_RUN=""

if [ "$2" = "--dry-run" ]; then
    DRY_RUN="true"
fi

if [ -n "$DRY_RUN" ]; then
    echo "DRY RUN MODE - No files will be moved"
    echo ""
fi

echo "Connecting to RetroPie..."
echo ""

if [ "$SYSTEM" = "all" ]; then
    echo "Checking all systems for nested directory issues..."
    echo ""

    ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << EOF
ROMS_BASE="\$HOME/RetroPie/roms"
FIXED_COUNT=0

for system_dir in "\$ROMS_BASE"/*; do
    if [ -d "\$system_dir" ]; then
        system=\$(basename "\$system_dir")

        # Skip special directories
        if [[ "\$system" == "downloaded_images" ]] || [[ "\$system" == "screenshots" ]]; then
            continue
        fi

        echo "Checking: \$system"

        # Look for subdirectories containing ROMs
        SUBDIRS=\$(find "\$system_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)

        if [ -n "\$SUBDIRS" ]; then
            for subdir in \$SUBDIRS; do
                ROM_COUNT=\$(find "\$subdir" -type f \( -iname "*.zip" -o -iname "*.nes" -o -iname "*.smc" -o -iname "*.sfc" -o -iname "*.n64" -o -iname "*.z64" -o -iname "*.gb" -o -iname "*.gbc" -o -iname "*.gba" -o -iname "*.gen" -o -iname "*.md" -o -iname "*.sms" -o -iname "*.gg" -o -iname "*.a26" -o -iname "*.bin" -o -iname "*.iso" -o -iname "*.cue" \) 2>/dev/null | wc -l | tr -d ' ')

                if [ "\$ROM_COUNT" -gt 0 ]; then
                    subdir_name=\$(basename "\$subdir")
                    echo "  Found nested directory: \$subdir_name (\$ROM_COUNT ROM(s))"

                    if [ -z "$DRY_RUN" ]; then
                        echo "    Moving ROMs to \$system/ root..."
                        mv "\$subdir"/* "\$system_dir/" 2>/dev/null || true
                        rmdir "\$subdir" 2>/dev/null || true
                        ((FIXED_COUNT++))
                    else
                        echo "    [DRY RUN] Would move \$ROM_COUNT ROM(s) to \$system/ root"
                    fi
                fi
            done
        fi

        echo ""
    fi
done

if [ -z "$DRY_RUN" ]; then
    if [ \$FIXED_COUNT -gt 0 ]; then
        echo "Fixed \$FIXED_COUNT system(s). Restarting EmulationStation..."
        sudo systemctl restart emulationstation
    else
        echo "No nested directory issues found!"
    fi
else
    echo "DRY RUN complete. Run without --dry-run to apply fixes."
fi
EOF

else
    echo "Checking $SYSTEM for nested directory issues..."
    echo ""

    ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << EOF
ROM_DIR="\$HOME/RetroPie/roms/$SYSTEM"

if [ ! -d "\$ROM_DIR" ]; then
    echo "Error: System '$SYSTEM' not found"
    exit 1
fi

cd "\$ROM_DIR"

# Look for subdirectories
SUBDIRS=\$(find . -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)

if [ -z "\$SUBDIRS" ]; then
    echo "No subdirectories found - ROM directory structure looks correct!"
    exit 0
fi

FOUND_ISSUE=false

for subdir in \$SUBDIRS; do
    # Count ROMs in subdirectory
    ROM_COUNT=\$(find "\$subdir" -type f \( -iname "*.zip" -o -iname "*.nes" -o -iname "*.smc" -o -iname "*.sfc" -o -iname "*.n64" -o -iname "*.z64" -o -iname "*.gb" -o -iname "*.gbc" -o -iname "*.gba" -o -iname "*.gen" -o -iname "*.md" -o -iname "*.sms" -o -iname "*.gg" -o -iname "*.a26" -o -iname "*.bin" -o -iname "*.iso" -o -iname "*.cue" \) 2>/dev/null | wc -l | tr -d ' ')

    if [ "\$ROM_COUNT" -gt 0 ]; then
        FOUND_ISSUE=true
        subdir_name=\$(basename "\$subdir")
        echo "Found nested directory: \$subdir_name"
        echo "  Contains: \$ROM_COUNT ROM(s)"
        echo ""

        if [ -z "$DRY_RUN" ]; then
            echo "Moving ROMs to $SYSTEM/ root directory..."
            mv "\$subdir"/* . 2>/dev/null || true
            rmdir "\$subdir" 2>/dev/null || true
            echo "  Moved \$ROM_COUNT ROM(s)"
            echo ""
        else
            echo "  [DRY RUN] Would move these \$ROM_COUNT ROM(s) to $SYSTEM/ root"
            echo ""
        fi
    fi
done

if [ "\$FOUND_ISSUE" = false ]; then
    echo "No nested directory issues found!"
    echo "ROM directory structure looks correct."
    exit 0
fi

if [ -z "$DRY_RUN" ]; then
    echo "Fixed nested directory structure!"
    echo ""
    echo "Restarting EmulationStation to reload game list..."
    sudo systemctl restart emulationstation
else
    echo "DRY RUN complete. Run without --dry-run to apply fixes."
fi
EOF
fi

echo ""
echo "Done!"
