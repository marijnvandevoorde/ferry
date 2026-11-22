#!/bin/bash
# Renders the brand assets into the app and site icon sets. Needs macOS, ImageMagick (magick) and Node with
# apps/desktop's dependencies installed.
#
#   brand/export.sh
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The scenic icon is a raster crop from the reference board, with the board's off-white paper in its corners
# and along its bottom edge. Trim 10 px all round and cut it to a clean rounded square on transparency.
magick brand/reference/ferry-app-icon-master-1024.png -alpha off -shave 10x10 -resize 1024x1024! \
    \( -size 1024x1024 xc:none -fill white -draw "roundrectangle 0,0 1023,1023 240,240" \) \
    -compose CopyOpacity -composite brand/icons/ferry-app-icon.png
FULL=brand/icons/ferry-app-icon.png

# The macOS icon grid: the rounded square is 824 of 1024 px.
magick "$FULL" -resize 824x824 -background none -gravity center -extent 1024x1024 "$WORK/mac.png"
# Apple touch icon: square and opaque, iOS rounds the corners itself.
magick "$FULL" -background "#1b2440" -alpha remove -alpha off "$WORK/touch.png"

size() { magick "$1" -filter Lanczos -resize "$2x$2" "$3"; }

# Mac app.
MAC=App/Assets.xcassets/AppIcon.appiconset
for spec in 16:1 16:2 32:1 32:2 128:1 128:2 256:1 256:2 512:1 512:2; do
    IFS=: read -r px scale <<<"$spec"
    size "$WORK/mac.png" $((px * scale)) "$MAC/icon_${px}x${px}@${scale}x.png"
done
# The icon on the connect screen (72 pt) and the menu bar template glyph.
size "$FULL" 144 App/Assets.xcassets/FerryMark.imageset/mark@1x.png
size "$FULL" 288 App/Assets.xcassets/FerryMark.imageset/mark@2x.png
cp brand/derived/glyph.svg App/Assets.xcassets/MenuBarIcon.imageset/menubar.svg

# Windows and Linux app.
(cd apps/desktop && npx tauri icon "../../$FULL" -o src-tauri/icons >/dev/null && rm -rf src-tauri/icons/android src-tauri/icons/ios)

# Site.
for px in 32 64 192 512; do size "$FULL" $px "site/img/icon-$px.png"; done
size "$WORK/touch.png" 180 site/img/icon-180.png

echo "exported icons"
