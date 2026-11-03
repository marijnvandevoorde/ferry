#!/bin/bash
# Renders the brand SVGs into the app and site icon sets. Needs macOS (sips), Google Chrome and Node with
# apps/desktop's dependencies installed.
#
#   brand/export.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# render svg size-inside-1024 background out: draws the SVG centred on a 1024 px canvas.
render() {
    cat > "$WORK/page.html" <<EOF
<!doctype html><body style="margin:0;background:transparent">
<div style="width:1024px;height:1024px;display:grid;place-items:center;background:$3">
<img src="file://$ROOT/$1" style="width:$2px;height:$2px"></div>
EOF
    "$CHROME" --headless --hide-scrollbars --force-device-scale-factor=1 --default-background-color=00000000 \
        --allow-file-access-from-files --window-size=1024,1024 --screenshot="$4" "file://$WORK/page.html" >/dev/null 2>&1
}

# The macOS icon grid: the rounded square is 824 of 1024 px.
render brand/icons/ferry-app-icon-dark.svg 824 transparent "$WORK/mac.png"
render brand/derived/app-icon-small.svg 824 transparent "$WORK/mac-small.png"
# Windows, Linux and the web: the full canvas.
render brand/icons/ferry-app-icon-dark.svg 1024 transparent "$WORK/full.png"
# Apple touch icon: square and opaque, iOS rounds the corners.
render brand/icons/ferry-app-icon-dark.svg 1024 "#1B2440" "$WORK/touch.png"

# Mac app. 16 and 32 px use the simplified ship.
MAC=App/Assets.xcassets/AppIcon.appiconset
for spec in 16:1:small 16:2:small 32:1:small 32:2:mac 128:1:mac 128:2:mac 256:1:mac 256:2:mac 512:1:mac 512:2:mac; do
    IFS=: read -r size scale source <<<"$spec"
    [ "$source" = small ] && src=$WORK/mac-small.png || src=$WORK/mac.png
    sips -z $((size * scale)) $((size * scale)) "$src" --out "$MAC/icon_${size}x${size}@${scale}x.png" >/dev/null
done

# Mac app images that stay vector: the menu bar glyph and the mark on the connect screen.
cp brand/derived/menubar.svg App/Assets.xcassets/MenuBarIcon.imageset/menubar.svg
cp brand/logos/ferry-mark-color.svg App/Assets.xcassets/FerryMark.imageset/mark-light.svg
cp brand/derived/mark-color-dark.svg App/Assets.xcassets/FerryMark.imageset/mark-dark.svg

# Windows and Linux app.
(cd apps/desktop && npx tauri icon "$WORK/full.png" -o src-tauri/icons >/dev/null && rm -rf src-tauri/icons/android src-tauri/icons/ios)

# Site.
cp brand/derived/favicon.svg site/img/favicon.svg
for size in 32 64 192 512; do sips -z $size $size "$WORK/full.png" --out "site/img/icon-$size.png" >/dev/null; done
sips -z 180 180 "$WORK/touch.png" --out site/img/icon-180.png >/dev/null

echo "exported icons"
