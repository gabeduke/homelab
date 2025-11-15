# RetroPie Device

## Connection Details

- **Purpose**: Game emulation for kids
- **OS**: RetroPie
- **Credentials**:
  - Username: `pi`
  - Password: `raspberry`
- **Network**: Connected via WiFi
- **Hostname**: `retropie.local`

## SSH Access

```bash
ssh pi@retropie.local
# Password: raspberry
# Or use SSH key for passwordless access
```

## Common Commands

### Check RetroPie Status
```bash
# Check if EmulationStation is running
ps aux | grep emulationstation

# Check system info
cat /etc/os-release

# Check RetroPie version
cat /opt/retropie/supplementary/emulationstation/VERSION
```

### Restart EmulationStation
```bash
# Restart EmulationStation from command line
sudo systemctl restart emulationstation

# Or reboot the whole system
sudo reboot
```

### RetroPie Configuration
```bash
# Launch RetroPie setup script
sudo /home/pi/RetroPie-Setup/retropie_setup.sh
```

### View EmulationStation Config
```bash
# Main config
cat /opt/retropie/configs/all/emulationstation/es_settings.cfg

# Per-user config
cat ~/.emulationstation/es_settings.cfg
```

### Check for Lock Files
```bash
# EmulationStation may create lock files that prevent starting
ls -la /tmp/.X*-lock
ls -la ~/.emulationstation/
```

## Troubleshooting

### Issue: Cannot Access Games - "Romset is unknown" Error
**Date**: 2024-11-14
**Symptom**: Kids went "menu diving" and games show "Romset is unknown" error when launching
**Status**: RESOLVED

#### Root Cause
The default NES emulator was changed to `lr-fbneo-nes` (an arcade emulator) which doesn't understand NES ROM formats.

#### Solution
Changed default emulator back to `lr-fceumm` (proper NES emulator):
```bash
ssh pi@retropie.local
sudo nano /opt/retropie/configs/nes/emulators.cfg
# Change: default = "lr-fbneo-nes"
# To: default = "lr-fceumm"
```

Or use the automated command:
```bash
ssh pi@retropie.local "sed -i 's/^default = \"lr-fbneo-nes\"/default = \"lr-fceumm\"/' /opt/retropie/configs/nes/emulators.cfg"
```

#### Lesson Learned
Always backup emulator configs before kids experiment with settings!

---

### Common Troubleshooting Steps

#### Investigation Steps for Game Issues
1. SSH into device to check current state
2. Check runcommand log: `cat /dev/shm/runcommand.log`
3. Check emulator configuration: `cat /opt/retropie/configs/<system>/emulators.cfg`
4. Check if EmulationStation is running: `ps aux | grep emulationstation`
5. Check game directories are intact: `ls ~/RetroPie/roms/<system>/`

#### Common Fixes
```bash
# Reset EmulationStation settings to defaults
mv ~/.emulationstation/es_settings.cfg ~/.emulationstation/es_settings.cfg.bak
sudo systemctl restart emulationstation

# Check if games directory is present
ls -la ~/RetroPie/roms/

# Restart EmulationStation
sudo systemctl restart emulationstation

# Full reboot
sudo reboot
```

## Useful Directories

- **ROMs**: `~/RetroPie/roms/`
- **BIOS files**: `~/RetroPie/BIOS/`
- **EmulationStation config**: `~/.emulationstation/`
- **RetroArch config**: `/opt/retropie/configs/all/retroarch.cfg`
- **Logs**: `/dev/shm/runcommand.log`, `~/.emulationstation/es_log.txt`

## Configuration Management

This repository includes scripts for managing RetroPie configurations:

- **Backup configs**: `devices/retropie/scripts/backup-configs.sh`
- **Restore configs**: `devices/retropie/scripts/restore-configs.sh`
- **Upload ROMs**: `devices/retropie/scripts/upload-roms.sh`
- **Install emulators**: `devices/retropie/scripts/install-emulator.sh`

See [retropie/README.md](./retropie/README.md) for detailed usage.

## Resources

- [RetroPie Documentation](https://retropie.org.uk/docs/)
- [EmulationStation Documentation](https://github.com/RetroPie/EmulationStation)
