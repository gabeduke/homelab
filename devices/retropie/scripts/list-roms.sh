#!/bin/bash
# List all ROMs currently on RetroPie, organized by system

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [system]"
    echo ""
    echo "List all ROMs on RetroPie, organized by system"
    echo ""
    echo "Examples:"
    echo "  $0              # List all ROMs on all systems"
    echo "  $0 snes         # List only SNES ROMs"
    echo "  $0 nes          # List only NES ROMs"
    exit 0
fi

SYSTEM="${1:-}"

if [ -n "$SYSTEM" ]; then
    echo "Listing ROMs for: $SYSTEM"
    echo ""

    ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << EOF
ROM_DIR="\$HOME/RetroPie/roms/$SYSTEM"

if [ ! -d "\$ROM_DIR" ]; then
    echo "Error: System '$SYSTEM' not found"
    exit 1
fi

echo "=== $SYSTEM ==="
echo ""

ROM_COUNT=0
for rom in "\$ROM_DIR"/*; do
    if [ -f "\$rom" ]; then
        filename=\$(basename "\$rom")
        # Skip gamelist.xml and other metadata files
        if [[ "\$filename" != "gamelist.xml" ]] && [[ "\$filename" != "." ]] && [[ "\$filename" != ".." ]]; then
            echo "  \$filename"
            ((ROM_COUNT++))
        fi
    fi
done

echo ""
echo "Total: \$ROM_COUNT ROM(s)"
EOF

else
    echo "Listing all ROMs on RetroPie..."
    echo ""

    ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << 'EOF'
ROMS_BASE="$HOME/RetroPie/roms"
TOTAL_ROMS=0

for system_dir in "$ROMS_BASE"/*; do
    if [ -d "$system_dir" ]; then
        system=$(basename "$system_dir")

        # Count ROMs (exclude directories and metadata files)
        ROM_COUNT=0
        for rom in "$system_dir"/*; do
            if [ -f "$rom" ]; then
                filename=$(basename "$rom")
                if [[ "$filename" != "gamelist.xml" ]] && [[ "$filename" != "." ]] && [[ "$filename" != ".." ]]; then
                    ((ROM_COUNT++))
                fi
            fi
        done

        if [ $ROM_COUNT -gt 0 ]; then
            echo "=== $system ==="
            echo ""

            for rom in "$system_dir"/*; do
                if [ -f "$rom" ]; then
                    filename=$(basename "$rom")
                    if [[ "$filename" != "gamelist.xml" ]]; then
                        echo "  $filename"
                    fi
                fi
            done

            echo ""
            echo "Subtotal: $ROM_COUNT ROM(s)"
            echo ""

            TOTAL_ROMS=$((TOTAL_ROMS + ROM_COUNT))
        fi
    fi
done

echo "========================================"
echo "TOTAL: $TOTAL_ROMS ROM(s) across all systems"
echo "========================================"
EOF
fi

echo ""
echo "To remove specific ROMs, use: ./remove-roms.sh <system> '<pattern>'"
