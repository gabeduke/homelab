#!/bin/bash
# Enable Kid Mode to prevent kids from changing settings

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

echo "Enabling Kid Mode for RetroPie..."
echo ""
echo "Kid Mode will:"
echo "  ✓ Show all games (no filtering)"
echo "  ✓ Hide RetroPie setup/configuration menus"
echo "  ✓ Disable quit/shutdown options"
echo "  ✓ Prevent changing settings"
echo "  ✓ Keep Comic Book theme active"
echo ""
echo "To exit Kid Mode: Press SELECT 4 times quickly"
echo ""

ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << 'EOF'
#!/bin/bash

ES_SETTINGS="$HOME/.emulationstation/es_settings.cfg"

# Backup current settings
cp "$ES_SETTINGS" "$ES_SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"

echo "Configuring Kid Mode settings..."

# Enable UI mode "Kid" (kiosk-like mode)
# This hides most menu options but shows all games
if grep -q "<string name=\"UIMode\"" "$ES_SETTINGS"; then
    # Update existing UIMode setting
    sed -i 's/<string name="UIMode" value="[^"]*"\/>/<string name="UIMode" value="Kid" \/>/' "$ES_SETTINGS"
    echo "  ✓ Updated UIMode to Kid"
else
    # Add UIMode setting before closing tag
    sed -i 's/<\/config>/<string name="UIMode" value="Kid" \/>\n<\/config>/' "$ES_SETTINGS"
    echo "  ✓ Added UIMode Kid setting"
fi

# Ensure favorites collection is enabled (kids' landing screen)
if ! grep -q "<bool name=\"FavoritesFirst\"" "$ES_SETTINGS"; then
    sed -i 's/<\/config>/<bool name="FavoritesFirst" value="true" \/>\n<\/config>/' "$ES_SETTINGS"
    echo "  ✓ Enabled Favorites collection"
fi

# Disable screensaver during gameplay (less confusing for kids)
if grep -q "<int name=\"ScreenSaverTime\"" "$ES_SETTINGS"; then
    sed -i 's/<int name="ScreenSaverTime" value="[^"]*"\/>/<int name="ScreenSaverTime" value="0" \/>/' "$ES_SETTINGS"
    echo "  ✓ Disabled screensaver"
else
    sed -i 's/<\/config>/<int name="ScreenSaverTime" value="0" \/>\n<\/config>/' "$ES_SETTINGS"
    echo "  ✓ Disabled screensaver"
fi

echo ""
echo "Kid Mode enabled!"
echo ""
echo "The kids can now:"
echo "  - Browse and play all games"
echo "  - Use favorites collection as landing screen"
echo "  - Navigate with all configured controllers"
echo ""
echo "The kids CANNOT:"
echo "  - Access RetroPie setup/configuration"
echo "  - Change UI settings or themes"
echo "  - Quit to terminal or shutdown the system"
echo "  - Delete or modify games"
echo ""
echo "To exit Kid Mode (for parents):"
echo "  Press SELECT button 4 times quickly while in EmulationStation"
echo ""

EOF

echo ""
echo "Kid Mode configuration complete!"
echo ""
echo "Restart EmulationStation to activate Kid Mode:"
echo "  ssh pi@retropie.local 'killall emulationstation'"
echo ""
echo "Or the system will apply the changes next time ES restarts"
echo ""
