#!/bin/bash
# Search the 1G1R ROM collection for specific games

set -e

# First try the repo directory, then fall back to ~/Downloads
ROM_COLLECTION_DIR="$(cd "$(dirname "$0")/.." && pwd)/roms/proper1g1r-collection/ROMs"
if [ ! -d "$ROM_COLLECTION_DIR" ] || [ -z "$(ls -A "$ROM_COLLECTION_DIR" 2>/dev/null)" ]; then
    ROM_COLLECTION_DIR="$HOME/Downloads/proper1g1r-collection/ROMs"
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <search-term> [system]"
    echo ""
    echo "Search the 1G1R ROM collection for games matching a keyword"
    echo ""
    echo "Available systems (optional filter):"
    echo "  nes snes n64 gb gbc gba genesis mastersystem gamegear atari2600"
    echo "  all - search all systems (default)"
    echo ""
    echo "Examples:"
    echo "  $0 Mario                    # Search for Mario games in all systems"
    echo "  $0 Zelda snes              # Search for Zelda games in SNES only"
    echo "  $0 'Ninja Turtles'         # Search for Ninja Turtles games"
    echo "  $0 TMNT                    # Search for TMNT games"
    echo "  $0 'Star Wars'             # Search for Star Wars games"
    echo "  $0 Sonic genesis           # Search for Sonic games in Genesis"
    exit 1
fi

SEARCH_TERM="$1"
SYSTEM_FILTER="${2:-all}"

# System mappings
get_zip_for_system() {
    case "$1" in
        nes) echo "Nintendo - Nintendo Entertainment System (Headerless).zip" ;;
        snes) echo "Nintendo - Super Nintendo Entertainment System.zip" ;;
        gb) echo "Nintendo - Game Boy.zip" ;;
        gbc) echo "Nintendo - Game Boy Color.zip" ;;
        gba) echo "Nintendo - Game Boy Advance.zip" ;;
        n64) echo "Nintendo - Nintendo 64 (BigEndian).zip" ;;
        genesis) echo "Sega - Mega Drive - Genesis.zip" ;;
        mastersystem) echo "Sega - Master System - Mark III.zip" ;;
        gamegear) echo "Sega - Game Gear.zip" ;;
        atari2600) echo "Atari - 2600.zip" ;;
        *) echo "" ;;
    esac
}

get_system_name() {
    case "$1" in
        "Nintendo - Nintendo Entertainment System (Headerless).zip") echo "NES" ;;
        "Nintendo - Super Nintendo Entertainment System.zip") echo "SNES" ;;
        "Nintendo - Game Boy.zip") echo "Game Boy" ;;
        "Nintendo - Game Boy Color.zip") echo "Game Boy Color" ;;
        "Nintendo - Game Boy Advance.zip") echo "Game Boy Advance" ;;
        "Nintendo - Nintendo 64 (BigEndian).zip") echo "Nintendo 64" ;;
        "Sega - Mega Drive - Genesis.zip") echo "Genesis" ;;
        "Sega - Master System - Mark III.zip") echo "Master System" ;;
        "Sega - Game Gear.zip") echo "Game Gear" ;;
        "Atari - 2600.zip") echo "Atari 2600" ;;
        *) echo "$1" ;;
    esac
}

if [ ! -d "$ROM_COLLECTION_DIR" ]; then
    echo "Error: ROM collection directory not found: $ROM_COLLECTION_DIR"
    echo ""
    echo "The 1G1R ROM collection should be placed in:"
    echo "  devices/retropie/roms/proper1g1r-collection/ROMs/"
    echo ""
    echo "Expected ZIP files:"
    echo "  - Nintendo - Nintendo Entertainment System (Headerless).zip"
    echo "  - Nintendo - Super Nintendo Entertainment System.zip"
    echo "  - Sega - Mega Drive - Genesis.zip"
    echo "  - etc."
    exit 1
fi

echo "Searching for: '$SEARCH_TERM'"
echo ""

TOTAL_MATCHES=0

if [ "$SYSTEM_FILTER" = "all" ]; then
    # Search all ZIP files
    for zip_file in "$ROM_COLLECTION_DIR"/*.zip; do
        if [ -f "$zip_file" ]; then
            zip_name=$(basename "$zip_file")
            system_name=$(get_system_name "$zip_name")

            # Search this ZIP file
            matches=$(unzip -l "$zip_file" 2>/dev/null | grep -i "$SEARCH_TERM" || true)

            if [ -n "$matches" ]; then
                echo "=== $system_name ==="
                echo ""
                echo "$matches" | awk '{$1=$2=$3=""; print $0}' | sed 's/^[[:space:]]*/  /'
                echo ""

                count=$(echo "$matches" | wc -l | tr -d ' ')
                TOTAL_MATCHES=$((TOTAL_MATCHES + count))
            fi
        fi
    done
else
    # Search specific system
    ZIP_FILE=$(get_zip_for_system "$SYSTEM_FILTER")

    if [ -z "$ZIP_FILE" ]; then
        echo "Error: Unknown system '$SYSTEM_FILTER'"
        exit 1
    fi

    ZIP_PATH="${ROM_COLLECTION_DIR}/${ZIP_FILE}"

    if [ ! -f "$ZIP_PATH" ]; then
        echo "Error: ROM archive not found: $ZIP_PATH"
        echo ""
        echo "Available ROM collections:"
        ls -1 "$ROM_COLLECTION_DIR"/*.zip 2>/dev/null || echo "  (none found)"
        exit 1
    fi

    system_name=$(get_system_name "$ZIP_FILE")
    echo "Searching in: $system_name"
    echo ""

    matches=$(unzip -l "$ZIP_PATH" 2>/dev/null | grep -i "$SEARCH_TERM" || true)

    if [ -n "$matches" ]; then
        echo "$matches" | awk '{$1=$2=$3=""; print $0}' | sed 's/^[[:space:]]*/  /'
        echo ""

        TOTAL_MATCHES=$(echo "$matches" | wc -l | tr -d ' ')
    fi
fi

if [ $TOTAL_MATCHES -eq 0 ]; then
    echo "No games found matching: '$SEARCH_TERM'"
    echo ""
    echo "Try broader search terms or check spelling"
else
    echo "=========================================="
    echo "Found $TOTAL_MATCHES game(s) matching '$SEARCH_TERM'"
    echo "=========================================="
    echo ""
    echo "To upload these games, use:"
    echo "  ./extract-and-upload.sh <system> '$SEARCH_TERM'"
fi
