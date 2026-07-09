#!/bin/bash
# Cuts a release: bumps the version, builds, packages the DMG, and drops
# both the DMG and its manifest into site/ ready for `vercel deploy`.
#
#   ./scripts/release.sh 0.3 "Geçmiş sayfası ve arama önerileri"
#
# The manifest (site/version.json) is what the running app polls. It MUST
# ship together with the DMG it describes — a manifest announcing a version
# whose DMG isn't up yet sends every user to a stale download.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
NOTES="${2:-}"

if [ -z "$VERSION" ]; then
  echo "usage: ./scripts/release.sh <version> [release notes]"
  echo "current: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
  exit 1
fi

CURRENT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
echo "→ $CURRENT → $VERSION"

# 1. Version the bundle. Both keys, so Finder and the update check agree.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Info.plist

# 2. Build + package. build.sh refuses to package a stale binary.
./build.sh
./scripts/make_dmg.sh

# 3. Stage both artefacts together.
cp build/YTMusic.dmg site/YTMusic.dmg
cat > site/version.json <<EOF
{
  "version": "$VERSION",
  "notes": "$NOTES",
  "dmg": "https://ytmusic-mac.vercel.app/YTMusic.dmg"
}
EOF

echo ""
echo "✓ site/YTMusic.dmg  ($(ls -lh site/YTMusic.dmg | awk '{print $5}'))"
echo "✓ site/version.json (v$VERSION)"
echo ""
echo "Next:"
echo "  git commit -am \"Release v$VERSION\" && git tag v$VERSION"
echo "  cd site && vercel deploy --prod"
echo ""
echo "Users see the update banner within 6 hours, or immediately via"
echo "the app menu → Güncellemeleri Denetle."
