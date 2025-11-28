#!/bin/bash
# Configure RetroArch to recognize the SNES controller in-game

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

echo "Configuring SNES controller for RetroArch (in-game)..."
echo ""
echo "The SNES controller works in EmulationStation but needs to be"
echo "configured separately for RetroArch (the emulator)."
echo ""
echo "METHOD 1: Configure in-game (Recommended)"
echo "==========================================="
echo "1. Launch any SNES game with the NES controller"
echo "2. Press Select + X to open RetroArch menu"
echo "3. Go to: Settings → Input"
echo "4. Select 'Port 1 Controls' or 'Port 2 Controls'"
echo "5. Set 'Device Index' to your SNES controller"
echo "   (should show as 'USB 2-axis 8-button gamepad')"
echo "6. Press Resume to go back to the game"
echo ""
echo "METHOD 2: Enable all controllers automatically"
echo "==============================================="
echo "Edit RetroArch config to auto-detect all controllers:"
echo ""

ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << 'EOF'
# Backup current config
cp /opt/retropie/configs/all/retroarch.cfg /opt/retropie/configs/all/retroarch.cfg.backup

# Enable auto-configuration for multiple controllers
if ! grep -q "input_player2_joypad_index" /opt/retropie/configs/all/retroarch.cfg; then
    echo "" >> /opt/retropie/configs/all/retroarch.cfg
    echo "# Auto-detect multiple controllers" >> /opt/retropie/configs/all/retroarch.cfg
    echo "input_player2_joypad_index = \"2\"" >> /opt/retropie/configs/all/retroarch.cfg
    echo "input_max_users = \"2\"" >> /opt/retropie/configs/all/retroarch.cfg
    echo "" >> /opt/retropie/configs/all/retroarch.cfg
    echo "✓ Added player 2 controller support to RetroArch config"
else
    echo "✓ RetroArch already configured for multiple controllers"
fi

echo ""
echo "Configuration updated!"
echo "Restart a game to test the SNES controller"
EOF

echo ""
echo "Done! The SNES controller should now work in-game."
echo ""
