#!/bin/bash
# Upload ROMs to RetroPie

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <system> <rom-file-or-directory>"
    echo ""
    echo "Examples:"
    echo "  $0 nes ~/Downloads/SuperMario.nes"
    echo "  $0 snes ~/Downloads/snes-games/"
    echo ""
    echo "Available systems:"
    echo "  nes, snes, n64, gb, gba, gbc, genesis, megadrive, psx, arcade, etc."
    exit 1
fi

SYSTEM="$1"
SOURCE="$2"

if [ ! -e "$SOURCE" ]; then
    echo "Error: Source file or directory does not exist: $SOURCE"
    exit 1
fi

echo "Uploading to RetroPie (${RETROPIE_HOST})..."
echo "  System: ${SYSTEM}"
echo "  Source: ${SOURCE}"
echo ""

# Create the system directory if it doesn't exist
ssh "${RETROPIE_USER}@${RETROPIE_HOST}" "mkdir -p ~/RetroPie/roms/${SYSTEM}"

# Upload the ROM(s)
if [ -d "$SOURCE" ]; then
    echo "Uploading directory contents..."
    scp -r "${SOURCE}"/* "${RETROPIE_USER}@${RETROPIE_HOST}:~/RetroPie/roms/${SYSTEM}/"
else
    echo "Uploading file..."
    scp "${SOURCE}" "${RETROPIE_USER}@${RETROPIE_HOST}:~/RetroPie/roms/${SYSTEM}/"
fi

echo ""
echo "Upload complete!"
echo "You may need to restart EmulationStation to see the new games."
echo "  ssh ${RETROPIE_USER}@${RETROPIE_HOST} 'sudo systemctl restart emulationstation'"
