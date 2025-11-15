#!/bin/bash
# Restore RetroPie configurations from this repository

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"
BACKUP_DIR="$(cd "$(dirname "$0")/.." && pwd)/configs"

echo "Restoring RetroPie configs to ${RETROPIE_HOST}..."
echo ""
echo "WARNING: This will overwrite existing configurations on the RetroPie!"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# Restore EmulationStation settings
if [ -f "${BACKUP_DIR}/emulationstation/es_settings.cfg" ]; then
    echo "  - EmulationStation settings..."
    scp "${BACKUP_DIR}/emulationstation/es_settings.cfg" \
        "${RETROPIE_USER}@${RETROPIE_HOST}:~/.emulationstation/es_settings.cfg"
fi

# Restore EmulationStation input config
if [ -f "${BACKUP_DIR}/emulationstation/es_input.cfg" ]; then
    echo "  - EmulationStation input config..."
    scp "${BACKUP_DIR}/emulationstation/es_input.cfg" \
        "${RETROPIE_USER}@${RETROPIE_HOST}:~/.emulationstation/es_input.cfg"
fi

# Restore RetroArch main config
if [ -f "${BACKUP_DIR}/retroarch/retroarch.cfg" ]; then
    echo "  - RetroArch main config..."
    scp "${BACKUP_DIR}/retroarch/retroarch.cfg" \
        "${RETROPIE_USER}@${RETROPIE_HOST}:/opt/retropie/configs/all/retroarch.cfg"
fi

# Restore emulator configs
echo "  - System emulator configs..."
if [ -d "${BACKUP_DIR}/emulators" ]; then
    for system_dir in "${BACKUP_DIR}/emulators"/*; do
        if [ -d "$system_dir" ]; then
            system=$(basename "$system_dir")
            if [ -f "${system_dir}/emulators.cfg" ]; then
                echo "    - ${system}"
                scp "${system_dir}/emulators.cfg" \
                    "${RETROPIE_USER}@${RETROPIE_HOST}:/opt/retropie/configs/${system}/emulators.cfg"
            fi
        fi
    done
fi

echo ""
echo "Restore complete!"
echo "You may need to restart EmulationStation: ssh ${RETROPIE_USER}@${RETROPIE_HOST} 'sudo systemctl restart emulationstation'"
