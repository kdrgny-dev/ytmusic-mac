#!/bin/bash
# Bundles the built .app into a distributable DMG with an /Applications
# symlink for drag-to-install and a plain-text first-launch note. The DMG
# is ad-hoc signed only, so the recipient has to right-click → Open the
# first time (instructions are in the DMG).
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="YTMusic"
VOLNAME="YTMusic"
DMG_FINAL="build/${NAME}.dmg"
STAGING="build/dmg-staging"

# 1. Make sure the app is built
if [ ! -d "build/${NAME}.app" ]; then
  echo "→ App not built yet; running build.sh"
  ./build.sh
fi

# 2. Stage contents
rm -rf "$STAGING" "$DMG_FINAL"
mkdir -p "$STAGING"
cp -R "build/${NAME}.app" "$STAGING/${NAME}.app"
ln -s /Applications "$STAGING/Applications"

# 3. First-launch instructions
cat > "$STAGING/READ ME — First Launch.txt" <<'EOF'
YTMUSIC — FIRST LAUNCH

This app isn't signed by an Apple Developer account, so macOS Gatekeeper
will block it the first time you open it with one of:

  "YTMusic cannot be opened because the developer cannot be verified"
  "YTMusic is damaged and can't be opened"

----------------------------------------------------------------
Install (one time)
----------------------------------------------------------------

1. Drag  YTMusic.app  to the  Applications  folder in this window.
2. Open  Applications  in Finder.
3. RIGHT-CLICK  YTMusic.app  →  Open.
4. In the dialog click  Open  again.

That's it. From now on, double-click works normally.

----------------------------------------------------------------
If it says "is damaged" instead
----------------------------------------------------------------

Open Terminal and paste:

  xattr -dr com.apple.quarantine /Applications/YTMusic.app

Then double-click the app normally.

----------------------------------------------------------------
Source
----------------------------------------------------------------

https://github.com/kdrgny-dev/ytmusic-mac
EOF

# 4. Create the DMG (compressed)
echo "→ Building DMG…"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_FINAL" >/dev/null

# 5. Cleanup
rm -rf "$STAGING"

echo ""
echo "✓ $DMG_FINAL"
ls -lh "$DMG_FINAL" | awk '{print "  Size: " $5}'
echo ""
echo "Send this DMG to your friend. They drag the app to Applications,"
echo "then RIGHT-CLICK → Open the first time (instructions are inside)."
