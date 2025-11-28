#!/bin/bash
# Install EmulationStation themes on RetroPie

set -e

RETROPIE_HOST="retropie.local"
RETROPIE_USER="pi"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <theme-name>"
    echo ""
    echo "Install a theme on RetroPie EmulationStation"
    echo ""
    echo "Recommended themes for kids:"
    echo "  comic-book          Comic book style (colorful, fun)"
    echo "  pixel               Retro pixel art style"
    echo "  tronkyfran          Bright neon style"
    echo "  epic-noir           Clean modern look"
    echo "  magazine-madness    Magazine cover style"
    echo "  crt                 Classic CRT TV look"
    echo "  snes-mini           SNES Classic menu style"
    echo ""
    echo "Popular adult themes:"
    echo "  art-book-next       Gallery art style"
    echo "  epicnoir            Minimalist dark theme"
    echo "  magazinemadness     Magazine layout"
    echo ""
    echo "Examples:"
    echo "  $0 comic-book       # Install Comic Book theme"
    echo "  $0 pixel            # Install Pixel theme"
    echo ""
    echo "To see all available themes, visit:"
    echo "  https://github.com/RetroPie/RetroPie-Setup/wiki/themes"
    exit 1
fi

THEME_NAME="$1"

echo "Installing theme: $THEME_NAME"
echo ""
echo "This will download and install the theme on RetroPie."
echo "You can change themes from EmulationStation: Start → UI Settings → Theme Set"
echo ""

ssh -t "${RETROPIE_USER}@${RETROPIE_HOST}" << EOF
# Install theme using RetroPie-Setup script
echo "Downloading theme..."

# Create themes directory if it doesn't exist
mkdir -p /opt/retropie/configs/all/emulationstation/themes

# Clone the theme repository
cd /opt/retropie/configs/all/emulationstation/themes

# Map common theme names to their repositories
case "$THEME_NAME" in
    comic-book|comicbook)
        REPO="https://github.com/TMNTturtleguy/es-theme-ComicBook.git"
        DIR="ComicBook"
        ;;
    pixel)
        REPO="https://github.com/ehettervik/es-theme-pixel.git"
        DIR="pixel"
        ;;
    tronkyfran)
        REPO="https://github.com/RetroPie/es-theme-tronkyfran.git"
        DIR="tronkyfran"
        ;;
    epic-noir|epicnoir)
        REPO="https://github.com/c64-dev/es-theme-epicnoir.git"
        DIR="epicnoir"
        ;;
    magazine-madness|magazinemadness)
        REPO="https://github.com/thelostsoul/es-theme-magazinemadness.git"
        DIR="magazinemadness"
        ;;
    crt)
        REPO="https://github.com/RetroPie/es-theme-crt.git"
        DIR="crt"
        ;;
    snes-mini|snesmini)
        REPO="https://github.com/ruckage/es-theme-snes-mini.git"
        DIR="snes-mini"
        ;;
    art-book-next)
        REPO="https://github.com/anthonycaccese/art-book-next-es.git"
        DIR="art-book-next-es"
        ;;
    *)
        echo "Unknown theme: $THEME_NAME"
        echo "You can manually install by providing a git repository URL"
        exit 1
        ;;
esac

# Check if theme already exists
if [ -d "\$DIR" ]; then
    echo "Theme \$DIR already exists. Updating..."
    cd "\$DIR"
    sudo git pull
else
    echo "Cloning \$REPO..."
    sudo git clone "\$REPO" "\$DIR"
fi

echo ""
echo "Theme installed successfully!"
echo ""
echo "To activate the theme:"
echo "  1. Restart EmulationStation (or press F4 and type 'emulationstation')"
echo "  2. Press Start → UI Settings → Theme Set"
echo "  3. Select the new theme"
echo ""

EOF

echo ""
echo "Installation complete!"
echo ""
echo "Available commands to change theme from SSH:"
echo "  killall emulationstation && emulationstation"
