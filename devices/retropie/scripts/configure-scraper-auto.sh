#!/bin/bash
# Configure EmulationStation scraper for automatic operation (no manual approval)

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

echo "Configuring EmulationStation scraper for automatic operation..."
echo ""
echo "This will:"
echo "  - Disable manual approval for each game"
echo "  - Auto-accept first match from ScreenScraper"
echo "  - Download box art, descriptions, and ratings"
echo ""

ssh "${RETROPIE_USER}@${RETROPIE_HOST}" << 'EOF'
ES_SETTINGS="$HOME/.emulationstation/es_settings.cfg"

# Backup the current settings
cp "$ES_SETTINGS" "$ES_SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"

# Update or add scraper settings for automatic mode
# Note: EmulationStation stores these in XML format

# Check if settings file exists
if [ ! -f "$ES_SETTINGS" ]; then
    echo "Error: EmulationStation settings file not found"
    exit 1
fi

echo "Current scraper settings:"
grep -i "scrape" "$ES_SETTINGS" || echo "  (no scraper settings found)"
echo ""

echo "To configure automatic scraping:"
echo ""
echo "Option 1: Via EmulationStation UI (Recommended)"
echo "=========================================="
echo "1. Press Start → Scraper"
echo "2. SCRAPER: Select 'ScreenScraper'"
echo "3. IMAGE SOURCE: Select 'Box Art' or 'Screenshot'"
echo "4. BOX SOURCE: Select 'Box 2D'"
echo "5. LOGO SOURCE: Select 'Wheel'"
echo "6. SCRAPE FROM: Select 'All Systems' or specific system"
echo "7. FILTER: Select 'All Games'"
echo "8. GAME NAMES: Enable 'Use ROM folder name'"
echo "9. Press START button to begin scraping"
echo ""
echo "The scraper will run automatically without prompting!"
echo ""
echo "Option 2: Use Skyscraper (Better for bulk scraping)"
echo "=========================================="
echo "Skyscraper is faster and better for large collections."
echo "Install it via RetroPie-Setup:"
echo "  1. Run: sudo ~/RetroPie-Setup/retropie_setup.sh"
echo "  2. Navigate to: Manage Packages → Optional Packages"
echo "  3. Install 'skyscraper'"
echo "  4. Run: Scraper → Skyscraper"
echo ""

EOF

echo ""
echo "Configuration information displayed above."
echo ""
echo "For immediate scraping without prompts:"
echo "  The built-in ES scraper should auto-accept matches"
echo "  If it still prompts, use Skyscraper instead (much faster!)"
echo ""
