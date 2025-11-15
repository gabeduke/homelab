# RetroPie Gaming Recommendations

**Hardware**: Raspberry Pi 4 Model B (8GB RAM)
**Current Status**: Excellent performance on NES games

## System Performance Guide

Based on your Pi 4 hardware, here's what runs well:

### ✅ Excellent Performance (Highly Recommended)

These systems will run flawlessly, great for kids:

1. **NES** (Nintendo Entertainment System) ✓ Already working great!
   - All games run perfectly
   - Current emulator: `lr-fceumm`

2. **SNES** (Super Nintendo)
   - 95%+ compatibility
   - Classics: Super Mario World, Donkey Kong Country, Zelda: A Link to the Past
   - Emulator: `lr-snes9x` (already installed)

3. **Game Boy / Game Boy Color** (GB/GBC)
   - Perfect compatibility
   - Great for kids: Pokemon, Kirby, Zelda
   - Emulator: `lr-gambatte` (already installed)

4. **Game Boy Advance** (GBA)
   - Excellent performance
   - Pokemon, Mario, Zelda, Metroid
   - Emulator: `lr-mgba` (already installed)

5. **Sega Genesis / Mega Drive**
   - Full speed on everything
   - Sonic series, Streets of Rage, Golden Axe
   - Emulator: `lr-genesis-plus-gx` (already installed)

6. **Sega Master System**
   - Perfect compatibility
   - Great library of games
   - Emulator: `lr-genesis-plus-gx` (already installed)

7. **Game Gear** (Sega handheld)
   - Runs great
   - Portable Sonic games
   - Emulator: `lr-genesis-plus-gx` (already installed)

8. **Atari 2600**
   - Classic arcade-style games
   - Simple controls, good for younger kids
   - Emulator: `lr-stella2014` (already installed)

### ⚠️ Good Performance (Most Games Work)

These systems run well but some demanding games may struggle:

9. **PlayStation 1** (PSX)
   - Most games run at full speed
   - 3D games may have slowdowns
   - Good: Crash Bandicoot, Spyro, Final Fantasy
   - Challenging: Gran Turismo, Metal Gear Solid
   - Emulator: `lr-pcsx-rearmed` (already installed)

10. **Nintendo 64** (N64)
    - 60-70% compatibility
    - 2D games and simple 3D work well
    - Good: Mario 64, Mario Kart 64, Kirby 64
    - Challenging: Perfect Dark, Conker, Goldeneye
    - Emulator: `lr-mupen64plus-next` (already installed)

11. **Neo Geo / Arcade** (MAME/FBNeo)
    - Most 2D arcade games work great
    - Fighting games like Metal Slug
    - Emulator: `lr-fbneo` (already installed)

### ❌ Limited Performance (Not Recommended for Pi 4)

These systems are too demanding for reliable play:

- **Nintendo DS** - Requires more CPU power
- **PSP** - Too demanding, even for Pi 4
- **Dreamcast** - Marginal performance, not worth it
- **GameCube/Wii** - Way too demanding
- **N64 (demanding titles)** - Some games won't run well

## Top Recommendations for Your Kids

Based on what works best on Pi 4, here are the best systems to focus on:

### Priority 1: Best Overall Experience
1. **SNES** - Best 16-bit era games, huge library
2. **GBA** - Modern pixel art, Pokemon is perfect for kids
3. **Sega Genesis** - Sonic games are always a hit

### Priority 2: Great Variety
4. **GB/GBC** - Classic Pokemon games (Red/Blue/Yellow/Gold/Silver)
5. **Game Gear** - Portable Sonic experience
6. **Atari 2600** - Simple, quick games (good for young kids)

### Priority 3: Advanced (if kids are older)
7. **PSX** - 3D adventure games (test performance first)
8. **N64** - Mario 64 and Mario Kart (classics only)

## Installing Additional Systems

Most emulators are already installed! You just need to add ROMs:

```bash
# Example: Add SNES games
cd ~/repos/homelab/devices/retropie/scripts
./upload-roms.sh snes ~/Downloads/super-mario-world.smc

# Example: Add Game Boy games
./upload-roms.sh gb ~/Downloads/pokemon-red.gb

# Example: Add GBA games
./upload-roms.sh gba ~/Downloads/pokemon-emerald.gba
```

After uploading, restart EmulationStation:
```bash
ssh pi@retropie.local 'sudo systemctl restart emulationstation'
```

## Performance Optimization Tips

If you experience slowdowns:

1. **Use recommended emulators** (see configurations)
2. **Close EmulationStation background processes**
3. **Overclock carefully** (Pi 4 can handle mild overclocking)
4. **Keep the Pi cool** (add heatsinks or fan)

### Check Current Overclock Status
```bash
ssh pi@retropie.local "vcgencmd measure_clock arm && vcgencmd measure_temp"
```

### Safe Pi 4 Overclock Settings
Edit `/boot/config.txt` (backup first!):
```
over_voltage=6
arm_freq=2000
gpu_freq=600
```

**Current temp: 33.1°C** - Your Pi is running cool, so you have headroom for overclocking if needed!

## Game Recommendations by System

### SNES (Top Picks for Kids)
- Super Mario World
- Super Mario Kart
- Donkey Kong Country 1, 2, 3
- Kirby Super Star
- Yoshi's Island
- Mega Man X

### GBA (Top Picks for Kids)
- Pokemon FireRed/LeafGreen
- Pokemon Emerald
- Mario Kart: Super Circuit
- Kirby: Nightmare in Dream Land
- Super Mario Advance series

### Genesis (Top Picks for Kids)
- Sonic the Hedgehog 1, 2, 3
- Sonic & Knuckles
- Streets of Rage 2
- Golden Axe
- Aladdin

### Game Boy/Color (Top Picks for Kids)
- Pokemon Red/Blue/Yellow
- Pokemon Gold/Silver/Crystal
- Super Mario Land 1, 2
- Kirby's Dream Land
- Tetris

## BIOS Requirements

Some systems need BIOS files (placed in `~/RetroPie/BIOS/`):

- **PSX**: `scph1001.bin`, `scph5501.bin`, `scph7001.bin`
- **GBA**: `gba_bios.bin` (optional, improves compatibility)

Note: BIOS files are copyrighted and must be obtained legally.

## Current Configuration Status

✅ All major emulators installed
✅ NES working perfectly with `lr-fceumm`
✅ System running cool at 33°C
✅ 8GB RAM - plenty for retro gaming
✅ 32 system directories configured

## Next Steps

1. Choose 2-3 systems from "Priority 1" recommendations
2. Obtain legal ROMs for those systems
3. Upload using `upload-roms.sh` script
4. Test games with your kids
5. Backup configs after finding good settings
6. Expand to more systems as interest grows

Remember: Focus on quality over quantity. A few great games on well-performing systems beats a huge library with performance issues!
