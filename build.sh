#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "→ Building (release)…"
swift build -c release

APP="build/YTMusic.app"
BIN_SRC=".build/release/YTMusicMac"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_SRC" "$APP/Contents/MacOS/YTMusicMac"
cp Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
  echo "→ Generating icon…"
  bash scripts/build_icon.sh
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so Gatekeeper / TCC treats it as a stable identity
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ Built $APP"
echo ""
echo "Run with:  open $APP"
echo "Or copy to /Applications:  cp -r $APP /Applications/"
