#!/bin/bash
# Backup RetroPie configurations to this repository

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"
BACKUP_DIR="$(cd "$(dirname "$0")/.." && pwd)/configs"

echo "Backing up RetroPie configs from ${RETROPIE_HOST}..."

# Create backup directory structure
mkdir -p "${BACKUP_DIR}/emulationstation"
mkdir -p "${BACKUP_DIR}/retroarch"
mkdir -p "${BACKUP_DIR}/emulators"

# Backup EmulationStation settings
echo "  - EmulationStation settings..."
scp "${RETROPIE_USER}@${RETROPIE_HOST}:~/.emulationstation/es_settings.cfg" \
    "${BACKUP_DIR}/emulationstation/es_settings.cfg"

# Backup EmulationStation input config
echo "  - EmulationStation input config..."
scp "${RETROPIE_USER}@${RETROPIE_HOST}:~/.emulationstation/es_input.cfg" \
    "${BACKUP_DIR}/emulationstation/es_input.cfg" 2>/dev/null || echo "    (no input config found)"

# Backup RetroArch main config
echo "  - RetroArch main config..."
scp "${RETROPIE_USER}@${RETROPIE_HOST}:/opt/retropie/configs/all/retroarch.cfg" \
    "${BACKUP_DIR}/retroarch/retroarch.cfg"

# Backup emulator configs for each system
echo "  - System emulator configs..."
SYSTEMS="nes snes n64 gb gba gbc genesis megadrive psx arcade mame-libretro"
for system in $SYSTEMS; do
    if ssh "${RETROPIE_USER}@${RETROPIE_HOST}" "test -f /opt/retropie/configs/${system}/emulators.cfg"; then
        echo "    - ${system}"
        mkdir -p "${BACKUP_DIR}/emulators/${system}"
        scp "${RETROPIE_USER}@${RETROPIE_HOST}:/opt/retropie/configs/${system}/emulators.cfg" \
            "${BACKUP_DIR}/emulators/${system}/emulators.cfg"
    fi
done

# Create a timestamp file
date > "${BACKUP_DIR}/last_backup.txt"

echo ""
echo "Backup complete! Files saved to: ${BACKUP_DIR}"
echo "Don't forget to commit these changes to git!"
