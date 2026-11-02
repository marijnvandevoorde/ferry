#!/bin/bash
# Regenerates site/img: icons from the app icon, the screenshots and the social card.
# Needs macOS (sips), Google Chrome, Python 3 and Node with apps/desktop's dependencies installed.
#
#   site/tools/assets.sh            everything
#   MAC_SCREENSHOT=path.png site/tools/assets.sh   use a real Mac screenshot instead of the drawing
set -euo pipefail
cd "$(dirname "$0")/.."
SITE=$PWD
IMG=$SITE/img
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
WORK=$(mktemp -d)
trap 'kill $SERVER 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkdir -p "$IMG"

shot() { # url width height out
    "$CHROME" --headless --hide-scrollbars --force-device-scale-factor=2 --default-background-color=00000000 \
        --virtual-time-budget=4000 --window-size="$2,$3" --screenshot="$4" "$1" >/dev/null 2>&1
}

# Icons
ICON=../App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
for size in 32 64 180 192 512; do sips -Z $size "$ICON" --out "$IMG/icon-$size.png" >/dev/null; done

# The Mac app: a real screenshot if given, otherwise the drawing in mockups/mac.html.
if [ -n "${MAC_SCREENSHOT:-}" ]; then
    sips -Z 1600 "$MAC_SCREENSHOT" --out "$IMG/screenshot-mac.png" >/dev/null
else
    shot "file://$SITE/tools/mockups/mac.html" 800 550 "$IMG/screenshot-mac.png"
fi

# The Windows/Linux app: its real UI, built with the Tauri APIs mocked and sample photos.
(cd ../apps/desktop && OUT_DIR=$WORK/desktop npx vite build --config "$SITE/tools/mockups/desktop/vite.config.mjs" >/dev/null)
python3 -m http.server 8765 --directory "$WORK/desktop" >/dev/null 2>&1 &
SERVER=$!
sleep 1
shot "http://localhost:8765/" 1100 720 "$IMG/screenshot-desktop.png"

# Social card
shot "file://$SITE/tools/mockups/og.html" 1200 630 "$WORK/og.png"
sips -z 630 1200 "$WORK/og.png" --out "$IMG/og-card.png" >/dev/null

ls -la "$IMG"
