#!/bin/bash
# Automatically scrape all games using command-line tools

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

echo "Auto-scraping all games in background..."
echo ""
echo "This will scrape:"
echo "  - NES games"
echo "  - SNES games"
echo "  - Genesis/Megadrive games"
echo ""
echo "Using ScreenScraper service (no manual approval needed)"
echo ""

# Run scraper in background on the Pi
ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << 'EOF' &
#!/bin/bash

# Function to scrape a system
scrape_system() {
    SYSTEM=$1
    echo "Scraping $SYSTEM..."

    # Use Steven Selph's scraper (pre-installed on RetroPie)
    /opt/retropie/supplementary/scraper/scraper -image_dir="/home/pi/.emulationstation/downloaded_images/${SYSTEM}" \
        -image_path="/home/pi/.emulationstation/downloaded_images/${SYSTEM}" \
        -rom_dir="/home/pi/RetroPie/roms/${SYSTEM}" \
        -output_file="/home/pi/RetroPie/roms/${SYSTEM}/gamelist.xml" \
        -console_src="ss" \
        -workers=4 \
        -skip_check \
        2>&1 | tee "/tmp/scraper_${SYSTEM}.log" || true

    echo "$SYSTEM scraping complete!"
}

echo "Starting background scraping at $(date)"
echo "Logs will be in /tmp/scraper_*.log"
echo ""

# Scrape each system
scrape_system "nes"
scrape_system "snes"
scrape_system "megadrive"

echo ""
echo "All scraping complete at $(date)"
echo "Restart EmulationStation to see the new artwork!"

EOF

echo "Scraping started in background on RetroPie!"
echo ""
echo "To check progress:"
echo "  ssh pi@retropie.local 'tail -f /tmp/scraper_nes.log'"
echo "  ssh pi@retropie.local 'tail -f /tmp/scraper_snes.log'"
echo "  ssh pi@retropie.local 'tail -f /tmp/scraper_megadrive.log'"
echo ""
echo "This will take 10-15 minutes for ~28 games"
echo ""
