#!/bin/bash
# Scrape metadata (cover art, descriptions, ratings) for ROMs using ScreenScraper
# This uses EmulationStation's built-in scraper via CLI

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <system> [options]"
    echo ""
    echo "Scrapes metadata (cover art, descriptions, ratings) for games on RetroPie"
    echo ""
    echo "Available systems:"
    echo "  nes snes n64 gb gbc gba genesis mastersystem gamegear atari2600 psx arcade"
    echo "  all - scrape all systems"
    echo ""
    echo "Options:"
    echo "  --force        Re-scrape even if metadata already exists"
    echo ""
    echo "Examples:"
    echo "  $0 snes                  # Scrape all SNES games without metadata"
    echo "  $0 nes --force           # Re-scrape all NES games"
    echo "  $0 all                   # Scrape all systems (takes a long time!)"
    echo ""
    echo "Note: This uses ScreenScraper service which may rate-limit requests."
    echo "      Consider creating a free account at screenscraper.fr for better limits."
    exit 1
fi

SYSTEM="$1"
FORCE_FLAG=""

if [ "$2" = "--force" ]; then
    FORCE_FLAG="--force"
fi

echo "Connecting to RetroPie..."
echo ""

if [ "$SYSTEM" = "all" ]; then
    echo "Scraping ALL systems (this will take a while)..."
    echo "Press Ctrl+C to cancel within 5 seconds..."
    sleep 5

    ssh -t "${RETROPIE_USER}@${RETROPIE_HOST}" << 'EOF'
echo "Starting metadata scraping for all systems..."
echo ""
echo "This will use the ScreenScraper service to download:"
echo "  - Cover art images"
echo "  - Game descriptions"
echo "  - Release dates"
echo "  - Ratings"
echo ""
echo "Please be patient, this may take 10-30 minutes depending on your library size."
echo ""

# Run the scraper for each system
for system in nes snes n64 gb gbc gba genesis mastersystem gamegear atari2600 psx arcade; do
    ROM_DIR="$HOME/RetroPie/roms/$system"
    if [ -d "$ROM_DIR" ] && [ "$(ls -A $ROM_DIR/*.* 2>/dev/null | wc -l)" -gt 0 ]; then
        echo "=========================================="
        echo "Scraping: $system"
        echo "=========================================="
        /opt/retropie/supplementary/scraper/scraper.sh "$system" || echo "Warning: Scraper failed for $system"
        echo ""
    fi
done

echo ""
echo "Scraping complete! Restarting EmulationStation to load new metadata..."
sudo systemctl restart emulationstation
EOF

else
    # Scrape single system
    echo "Scraping metadata for $SYSTEM games..."
    echo ""

    ssh -t "${RETROPIE_USER}@${RETROPIE_HOST}" << EOF
ROM_DIR="\$HOME/RetroPie/roms/$SYSTEM"

if [ ! -d "\$ROM_DIR" ]; then
    echo "Error: System '$SYSTEM' not found on RetroPie"
    exit 1
fi

ROM_COUNT=\$(ls -1 "\$ROM_DIR"/*.* 2>/dev/null | wc -l | tr -d ' ')

if [ "\$ROM_COUNT" -eq 0 ]; then
    echo "Error: No ROMs found in \$ROM_DIR"
    exit 1
fi

echo "Found \$ROM_COUNT ROM(s) in $SYSTEM"
echo ""
echo "Downloading metadata from ScreenScraper..."
echo "  - Cover art images"
echo "  - Game descriptions"
echo "  - Release dates"
echo "  - Ratings"
echo ""
echo "This may take a few minutes depending on your library size."
echo ""

# Run scraper using RetroPie-Setup
# This will install and run the scraper if needed
sudo /home/pi/RetroPie-Setup/retropie_packages.sh scraper || {
    echo ""
    echo "Scraper encountered an error. This could be due to:"
    echo "  - Rate limiting from ScreenScraper (wait a few minutes)"
    echo "  - Network connectivity issues"
    echo "  - ROM file names not matching database"
    echo ""
    echo "To manually scrape from EmulationStation UI:"
    echo "  1. Start menu -> Scraper"
    echo "  2. Select systems to scrape"
    echo "  3. Start scraping"
    exit 1
}

echo ""
echo "Scraping complete! Restarting EmulationStation..."
sudo systemctl restart emulationstation
EOF
fi

echo ""
echo "Done! Your games should now have cover art and metadata."
echo ""
echo "If some games are still missing artwork:"
echo "  1. Check ROM file naming (should match official game names)"
echo "  2. Use RetroPie's built-in scraper (Start menu -> Scraper)"
echo "  3. Manually scrape from EmulationStation UI for better control"
