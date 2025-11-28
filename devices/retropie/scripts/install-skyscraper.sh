#!/bin/bash
# Install and configure Skyscraper - a better scraper for bulk operations

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

echo "Installing Skyscraper - Better scraper for bulk operations"
echo ""
echo "Skyscraper advantages:"
echo "  - No manual approval needed"
echo "  - Much faster (caches results)"
echo "  - Better artwork quality"
echo "  - Runs in background"
echo ""

ssh -t "${RETROPIE_USER}@${RETROPIE_HOST}" << 'EOF'
echo "Installing Skyscraper via RetroPie-Setup..."
echo ""

# Install Skyscraper
cd ~/RetroPie-Setup
sudo ./retropie_packages.sh skyscraper

echo ""
echo "Skyscraper installed!"
echo ""
echo "To scrape all games automatically:"
echo "  Skyscraper -p nes -s screenscraper"
echo "  Skyscraper -p snes -s screenscraper"
echo "  Skyscraper -p megadrive -s screenscraper"
echo ""
echo "To generate game lists:"
echo "  Skyscraper -p nes"
echo "  Skyscraper -p snes"
echo "  Skyscraper -p megadrive"
echo ""
EOF

echo ""
echo "Installation complete!"
echo ""
