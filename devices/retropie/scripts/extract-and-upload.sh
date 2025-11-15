#!/bin/bash
# Extract ROMs from zip archives and upload to RetroPie

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"
ROM_COLLECTION_DIR="$(cd "$(dirname "$0")/.." && pwd)/roms/proper1g1r-collection/ROMs"

# System mappings: retropie system -> zip name
get_zip_for_system() {
    case "$1" in
        nes) echo "Nintendo - Nintendo Entertainment System (Headerless).zip" ;;
        snes) echo "Nintendo - Super Nintendo Entertainment System.zip" ;;
        gb) echo "Nintendo - Game Boy.zip" ;;
        gbc) echo "Nintendo - Game Boy Color.zip" ;;
        gba) echo "Nintendo - Game Boy Advance.zip" ;;
        n64) echo "Nintendo - Nintendo 64 (BigEndian).zip" ;;
        genesis) echo "Sega - Mega Drive - Genesis.zip" ;;
        mastersystem) echo "Sega - Master System - Mark III.zip" ;;
        gamegear) echo "Sega - Game Gear.zip" ;;
        atari2600) echo "Atari - 2600.zip" ;;
        *) echo "" ;;
    esac
}

if [ $# -lt 1 ]; then
    echo "Usage: $0 <system> [--all | <rom-name-pattern>]"
    echo ""
    echo "Available systems:"
    echo "  nes snes n64 gb gbc gba genesis mastersystem gamegear atari2600"
    echo ""
    echo "Examples:"
    echo "  $0 nes --all                    # Upload all NES games"
    echo "  $0 snes 'Super Mario*'          # Upload all Super Mario SNES games"
    echo "  $0 gba Pokemon                  # Upload all GBA Pokemon games"
    echo "  $0 genesis Sonic                # Upload all Genesis Sonic games"
    exit 1
fi

SYSTEM="$1"
PATTERN="${2:-}"

# Find the zip file for this system
ZIP_FILE=$(get_zip_for_system "$SYSTEM")

if [ -z "$ZIP_FILE" ]; then
    echo "Error: Unknown system '$SYSTEM'"
    exit 1
fi

ZIP_PATH="${ROM_COLLECTION_DIR}/${ZIP_FILE}"

if [ ! -f "$ZIP_PATH" ]; then
    echo "Error: ROM archive not found: $ZIP_PATH"
    exit 1
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Extracting ROMs from $ZIP_FILE..."

if [ "$PATTERN" = "--all" ]; then
    echo "Extracting ALL games (this may take a while)..."
    unzip -q "$ZIP_PATH" -d "$TEMP_DIR"
else
    echo "Extracting games matching: $PATTERN"
    unzip -q "$ZIP_PATH" "*${PATTERN}*" -d "$TEMP_DIR" 2>/dev/null || {
        echo "No ROMs found matching pattern: $PATTERN"
        echo ""
        echo "Available ROMs (first 20):"
        unzip -l "$ZIP_PATH" | head -30
        exit 1
    }
fi

# Count extracted files
ROM_COUNT=$(find "$TEMP_DIR" -type f | wc -l | tr -d ' ')

if [ "$ROM_COUNT" -eq 0 ]; then
    echo "No ROMs extracted!"
    exit 1
fi

echo "Found $ROM_COUNT ROM(s) to upload"
echo ""

# Create system directory on RetroPie
ssh "${RETROPIE_USER}@${RETROPIE_HOST}" "mkdir -p ~/RetroPie/roms/${SYSTEM}"

# Upload the ROMs
echo "Uploading to RetroPie..."
scp -r "$TEMP_DIR"/* "${RETROPIE_USER}@${RETROPIE_HOST}:~/RetroPie/roms/${SYSTEM}/"

echo ""
echo "Upload complete! Uploaded $ROM_COUNT ROM(s) to ${SYSTEM}"
echo ""
echo "To see the new games, restart EmulationStation:"
echo "  ssh ${RETROPIE_USER}@${RETROPIE_HOST} 'sudo systemctl restart emulationstation'"
