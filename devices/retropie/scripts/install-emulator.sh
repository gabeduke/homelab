#!/bin/bash
# Install additional emulators on RetroPie

set -e

RETROPIE_HOST="${RETROPIE_HOST:-retropie.local}"
RETROPIE_USER="${RETROPIE_USER:-pi}"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <package-name>"
    echo ""
    echo "This script helps install additional emulators using the RetroPie-Setup script."
    echo ""
    echo "Common packages:"
    echo "  lr-ppsspp          - PSP emulator"
    echo "  lr-desmume         - Nintendo DS emulator"
    echo "  lr-dolphin         - GameCube/Wii emulator"
    echo "  lr-mupen64plus     - N64 emulator (alternative)"
    echo "  lr-flycast         - Dreamcast emulator"
    echo ""
    echo "To see all available packages, run the RetroPie-Setup script manually:"
    echo "  ssh ${RETROPIE_USER}@${RETROPIE_HOST} 'sudo /home/pi/RetroPie-Setup/retropie_setup.sh'"
    exit 1
fi

PACKAGE="$1"

echo "Installing ${PACKAGE} on RetroPie (${RETROPIE_HOST})..."
echo ""
echo "This will run the RetroPie-Setup script to install the package."
echo "The installation may take several minutes depending on the package."
echo ""

# Run the RetroPie setup script to install the package
ssh -t "${RETROPIE_USER}@${RETROPIE_HOST}" \
    "sudo /home/pi/RetroPie-Setup/retropie_setup.sh ${PACKAGE} install"

echo ""
echo "Installation complete!"
echo "Don't forget to backup your configs after testing the new emulator:"
echo "  ./backup-configs.sh"
