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
    ├── backup-configs.sh         # Backup configs from RetroPie to repo
    ├── restore-configs.sh        # Restore configs from repo to RetroPie
    ├── upload-roms.sh            # Upload ROM files to RetroPie
    ├── extract-and-upload.sh     # Extract from 1G1R collection and upload
    ├── install-emulator.sh       # Install new emulators
    ├── scrape-metadata.sh        # Scrape cover art and metadata
    ├── list-roms.sh              # List all ROMs on the device
    ├── remove-roms.sh            # Remove ROMs (for cleaning duplicates)
    └── fix-nested-navigation.sh  # Fix nested directory structure issues
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

### Extract and Upload from 1G1R Collection

Extract ROMs from the curated 1G1R (One Game One ROM) collection and upload them:

```bash
cd devices/retropie/scripts

# Upload all NES games
./extract-and-upload.sh nes --all

# Upload specific games using pattern matching
./extract-and-upload.sh snes 'Super Mario*'
./extract-and-upload.sh gba Pokemon
./extract-and-upload.sh genesis Sonic
```

The 1G1R collection contains curated, high-quality ROMs with no duplicates. This is the recommended way to add games!

### Scrape Metadata and Cover Art

Download cover art, descriptions, and ratings for your games:

```bash
cd devices/retropie/scripts

# Scrape cover art for all SNES games
./scrape-metadata.sh snes

# Re-scrape all NES games (even if metadata exists)
./scrape-metadata.sh nes --force

# Scrape all systems (takes a long time!)
./scrape-metadata.sh all
```

This uses the ScreenScraper service to fetch high-quality artwork and metadata. Rate limiting may apply.

### List ROMs

See what ROMs are currently installed:

```bash
cd devices/retropie/scripts

# List all ROMs on all systems
./list-roms.sh

# List only SNES ROMs
./list-roms.sh snes
```

### Remove ROMs (Cleanup Duplicates)

Remove unwanted ROMs to clean up your collection:

```bash
cd devices/retropie/scripts

# Always preview first with --dry-run!
./remove-roms.sh snes 'Zelda*' --dry-run

# Remove all Japanese versions to reduce clutter
./remove-roms.sh snes '*Japan*'
./remove-roms.sh snes '*J)*'

# Remove revision ROMs (Rev A, Rev B, etc.)
./remove-roms.sh snes '*Rev*'

# Remove beta/prototype versions
./remove-roms.sh nes '*Beta*'

# Remove ROM hacks
./remove-roms.sh nes '*Hack*'
```

Common patterns to clean up:
- `'*Japan*'` or `'*J)*'` - Japanese versions
- `'*Europe*'` or `'*E)*'` - European versions
- `'*Rev*'` - Revised versions (Rev A, Rev B, etc)
- `'*Beta*'` - Beta/prototype versions
- `'*Hack*'` - ROM hacks
- `'*Unl*'` - Unlicensed games

### Fix Nested Navigation Issues

If you have to navigate into a subfolder to see your games:

```bash
cd devices/retropie/scripts

# Check for nested directory issues (preview)
./fix-nested-navigation.sh snes --dry-run

# Fix nested directories
./fix-nested-navigation.sh snes

# Fix all systems
./fix-nested-navigation.sh all
```

This moves ROMs from subdirectories to the correct system root directory.

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

### Cleaning Up Your Game Library

If you have too many similar titles (e.g., 15 Zeldas!) and missing cover art:

1. **First, list what you have:**
   ```bash
   cd devices/retropie/scripts
   ./list-roms.sh snes
   ```

2. **Preview what you want to remove:**
   ```bash
   # See which games would be deleted (dry run!)
   ./remove-roms.sh snes '*Japan*' --dry-run
   ./remove-roms.sh snes '*Europe*' --dry-run
   ./remove-roms.sh snes '*Rev*' --dry-run
   ./remove-roms.sh snes 'Zelda*' --dry-run  # Check all Zelda games
   ```

3. **Remove unwanted duplicates:**
   ```bash
   # Keep only USA versions, remove others
   ./remove-roms.sh snes '*Japan*'
   ./remove-roms.sh snes '*Europe*'
   ./remove-roms.sh snes '*Rev*'

   # Or manually curate specific series
   # Keep only: "Zelda - A Link to the Past"
   # Remove: "Zelda - A Link to the Past (Rev 1)", etc.
   ```

4. **Fix nested navigation (if SNES games are in a subfolder):**
   ```bash
   ./fix-nested-navigation.sh snes --dry-run  # Preview
   ./fix-nested-navigation.sh snes            # Fix it
   ```

5. **Scrape cover art for remaining games:**
   ```bash
   ./scrape-metadata.sh snes
   ```

6. **Verify the cleanup:**
   ```bash
   ./list-roms.sh snes
   ```

Result: A curated, kid-friendly library with cover art and no overwhelming duplicates!

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
