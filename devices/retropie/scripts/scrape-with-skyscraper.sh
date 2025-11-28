#!/bin/bash
# Use Skyscraper for automatic scraping (better than Steven Selph's scraper)

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

echo "Installing and running Skyscraper for automatic scraping..."
echo ""
echo "Skyscraper is the best scraper for RetroPie:"
echo "  - Fast with caching"
echo "  - Better artwork"
echo "  - No manual approval"
echo ""

ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << 'EOF'
#!/bin/bash

# Check if Skyscraper is installed
if ! command -v Skyscraper &> /dev/null; then
    echo "Installing Skyscraper..."
    cd ~/RetroPie-Setup
    sudo ./retropie_packages.sh skyscraper
fi

echo ""
echo "Scraping NES games..."
Skyscraper -p nes -s screenscraper --videos --flags unattend
Skyscraper -p nes

echo ""
echo "Scraping SNES games..."
Skyscraper -p snes -s screenscraper --videos --flags unattend
Skyscraper -p snes

echo ""
echo "Scraping Genesis/Megadrive games..."
Skyscraper -p megadrive -s screenscraper --videos --flags unattend
Skyscraper -p megadrive

echo ""
echo "All scraping complete!"
echo "Restarting EmulationStation..."
killall emulationstation 2>/dev/null || true
sleep 2
emulationstation &

EOF

echo ""
echo "Scraping complete! EmulationStation restarted with new artwork."
