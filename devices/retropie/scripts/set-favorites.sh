#!/bin/bash
# Set favorites for EmulationStation - kid-friendly landing screen

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

echo "Setting up favorites for kids' landing screen..."
echo ""
echo "Favorites to configure:"
echo "  - Super Mario Bros. (NES)"
echo "  - Pokemon Crystal (GBC)"
echo "  - Pokemon FireRed (GBA)"
echo "  - Sonic The Hedgehog 2 (Genesis)"
echo "  - TMNT IV: Turtles in Time (SNES)"
echo "  - Super Star Wars (SNES)"
echo "  - Super Mario 64 (N64)"
echo ""

ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << 'EOF'
#!/bin/bash

# Function to add favorite tag to a ROM in gamelist.xml
add_favorite() {
    local SYSTEM=$1
    local ROM_NAME=$2
    local GAMELIST="/home/pi/RetroPie/roms/${SYSTEM}/gamelist.xml"

    echo "Adding favorite: ${ROM_NAME} (${SYSTEM})"

    # Check if gamelist exists
    if [ ! -f "$GAMELIST" ]; then
        echo "  Warning: gamelist.xml not found for ${SYSTEM}, skipping"
        return
    fi

    # Find the game entry and add favorite tag if not present
    # This is a simple approach - look for the path and add <favorite>true</favorite>
    if grep -q "<path>.*${ROM_NAME}" "$GAMELIST"; then
        # Create backup
        cp "$GAMELIST" "${GAMELIST}.backup.$(date +%Y%m%d_%H%M%S)"

        # Add favorite tag if not already present
        if ! grep -A5 "<path>.*${ROM_NAME}" "$GAMELIST" | grep -q "<favorite>"; then
            # Use sed to add favorite tag after the game entry
            sed -i "/<path>.*${ROM_NAME}/a\\    <favorite>true</favorite>" "$GAMELIST"
            echo "  ✓ Added to favorites"
        else
            echo "  ✓ Already in favorites"
        fi
    else
        echo "  Warning: ${ROM_NAME} not found in ${SYSTEM} gamelist"
    fi
}

# Set favorites for best games from each franchise
add_favorite "nes" "Super Mario Bros"
add_favorite "gbc" "Pokemon - Crystal"
add_favorite "gba" "Pokemon - FireRed"
add_favorite "megadrive" "Sonic The Hedgehog 2"
add_favorite "snes" "Teenage Mutant Ninja Turtles IV - Turtles in Time"
add_favorite "snes" "Super Star Wars"
add_favorite "n64" "Super Mario 64"

echo ""
echo "Favorites configured!"
echo "Restart EmulationStation to see changes"

EOF

echo ""
echo "Favorites setup complete!"
echo ""
echo "To see favorites in EmulationStation:"
echo "  1. Restart EmulationStation (or it will restart after scraping)"
echo "  2. Press Select to bring up the menu"
echo "  3. Choose 'Game Collection Settings'"
echo "  4. Enable 'Favorites' collection"
echo "  5. The favorites will appear as a collection on the main menu"
echo ""
