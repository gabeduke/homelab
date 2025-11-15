# RetroPie Configuration Management

This directory contains scripts and backed-up configurations for the RetroPie device.

## Directory Structure

```
retropie/
├── configs/              # Backed-up configurations (gitignored by default for ROMs)
│   ├── emulationstation/ # EmulationStation settings
│   ├── retroarch/        # RetroArch global config
│   └── emulators/        # Per-system emulator configs
└── scripts/              # Management scripts
    ├── backup-configs.sh   # Backup configs from RetroPie to repo
    ├── restore-configs.sh  # Restore configs from repo to RetroPie
    ├── upload-roms.sh      # Upload ROM files to RetroPie
    └── install-emulator.sh # Install new emulators
```

## Scripts Usage

### Backup Configurations

Backup all RetroPie configurations to this repository:

```bash
cd devices/retropie/scripts
./backup-configs.sh
```

This backs up:
- EmulationStation settings (UI preferences, themes, etc.)
- RetroArch global configuration
- Per-system emulator configurations
- Controller mappings

**Important**: After backing up, commit the changes to git to keep them versioned!

### Restore Configurations

Restore configurations from this repository to the RetroPie:

```bash
cd devices/retropie/scripts
./restore-configs.sh
```

This is useful when:
- Setting up a new RetroPie device
- Recovering from kids changing settings
- Rolling back problematic configuration changes

### Upload ROMs

Upload ROM files to the RetroPie:

```bash
cd devices/retropie/scripts

# Upload a single ROM
./upload-roms.sh nes ~/Downloads/SuperMario.nes

# Upload a directory of ROMs
./upload-roms.sh snes ~/Downloads/snes-games/
```

**Note**: ROMs are NOT backed up in this repository due to copyright/size concerns. Keep your ROM collection backed up separately.

### Install New Emulators

Install additional emulators or cores:

```bash
cd devices/retropie/scripts

# Install PSP emulator
./install-emulator.sh lr-ppsspp

# Install Nintendo DS emulator
./install-emulator.sh lr-desmume
```

After installing new emulators, run `./backup-configs.sh` to save the configuration!

## Available Systems

Common systems supported by RetroPie:
- `nes` - Nintendo Entertainment System
- `snes` - Super Nintendo
- `n64` - Nintendo 64
- `gb` - Game Boy
- `gbc` - Game Boy Color
- `gba` - Game Boy Advance
- `genesis` / `megadrive` - Sega Genesis/Mega Drive
- `mastersystem` - Sega Master System
- `psx` - PlayStation 1
- `arcade` - Arcade games (MAME)
- `neogeo` - Neo Geo
- `atari2600` - Atari 2600

## Common Workflows

### After Kids Change Settings

1. Backup current state (might be useful to see what changed):
   ```bash
   ./backup-configs.sh
   git diff
   ```

2. If needed, restore known-good config:
   ```bash
   git checkout -- ../configs/
   ./restore-configs.sh
   ```

### Adding New Games

1. Upload ROMs:
   ```bash
   ./upload-roms.sh <system> <rom-files>
   ```

2. Restart EmulationStation to see new games:
   ```bash
   ssh pi@retropie.local 'sudo systemctl restart emulationstation'
   ```

### Trying New Emulators

1. Install the emulator:
   ```bash
   ./install-emulator.sh <package-name>
   ```

2. Test it with some games

3. If it works well, backup the config:
   ```bash
   ./backup-configs.sh
   git add ../configs/
   git commit -m "Add <emulator-name> configuration"
   ```

## Git Considerations

### What to Commit
- Configuration files (emulators.cfg, retroarch.cfg, etc.)
- EmulationStation settings
- Scripts and documentation

### What NOT to Commit
- ROM files (copyright issues, large files)
- BIOS files (copyright issues)
- Save states (personal progress, large files)
- Screenshots/videos

Consider adding to `.gitignore`:
```
devices/retropie/roms/
devices/retropie/bios/
devices/retropie/saves/
*.srm
*.state
```

## Troubleshooting

See [retropie.md](../retropie.md) for detailed troubleshooting steps.
