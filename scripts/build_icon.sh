#!/bin/bash
# Generates AppIcon.icns from the Swift icon renderer.
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p build
BASE="build/icon-1024.png"
SET="build/AppIcon.iconset"

swift scripts/make_icon.swift "$BASE"

rm -rf "$SET"
mkdir -p "$SET"

sips -z 16 16     "$BASE" --out "$SET/icon_16x16.png"       >/dev/null
sips -z 32 32     "$BASE" --out "$SET/icon_16x16@2x.png"    >/dev/null
sips -z 32 32     "$BASE" --out "$SET/icon_32x32.png"       >/dev/null
sips -z 64 64     "$BASE" --out "$SET/icon_32x32@2x.png"    >/dev/null
sips -z 128 128   "$BASE" --out "$SET/icon_128x128.png"     >/dev/null
sips -z 256 256   "$BASE" --out "$SET/icon_128x128@2x.png"  >/dev/null
sips -z 256 256   "$BASE" --out "$SET/icon_256x256.png"     >/dev/null
sips -z 512 512   "$BASE" --out "$SET/icon_256x256@2x.png"  >/dev/null
sips -z 512 512   "$BASE" --out "$SET/icon_512x512.png"     >/dev/null
cp "$BASE"                    "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o build/AppIcon.icns
echo "✓ build/AppIcon.icns"
