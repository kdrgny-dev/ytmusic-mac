#!/bin/bash
# Cuts a release end to end: bumps the version, builds, packages the DMG,
# publishes it to GitHub Releases, and deploys the update manifest.
#
#   ./scripts/release.sh 0.3 "Geçmiş sayfası ve arama önerileri"
#
# Single source of truth for the download: the DMG lives ONLY in GitHub
# Releases. The site and the manifest both link to the release's permanent
#   .../releases/latest/download/YTMusic.dmg
# URL, so nothing ever has to copy a 2 MB binary into the repo again.
#
# The manifest (site/version.json) is what the running app polls for the
# version number and notes. It MUST go live only AFTER the GitHub release
# exists — a manifest announcing a version whose release isn't published yet
# points `latest` at the old DMG.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
# NOTES go into the GitHub release AND the update manifest — write them in
# ENGLISH (the site, repo and releases are all English), not Turkish.
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

# 3. Manifest points at GitHub's permanent latest-download URL. This string
#    never changes between releases, but rewrite it each time so an older
#    checkout that still had the Vercel URL gets corrected.
REPO="kdrgny-dev/ytmusic-mac"
cat > site/version.json <<EOF
{
  "version": "$VERSION",
  "notes": "$NOTES",
  "dmg": "https://github.com/$REPO/releases/latest/download/YTMusic.dmg"
}
EOF
echo "✓ site/version.json (v$VERSION)"

# 4. Commit the version bump + manifest, tag, push.
git commit -aqm "Release v$VERSION"
git tag "v$VERSION"
git push -q origin HEAD
git push -q origin "v$VERSION"
echo "✓ pushed commit + tag v$VERSION"

# 5. Publish the DMG to GitHub Releases. This is what makes `latest/download`
#    resolve — the site and manifest are useless until it exists. The asset
#    MUST be named YTMusic.dmg for the permanent URL to hit it.
gh release create "v$VERSION" build/YTMusic.dmg \
  --title "v$VERSION" \
  --notes "$NOTES"
echo "✓ GitHub release v$VERSION published with DMG"

# 6. Deploy the manifest LAST, now that `latest` resolves to this version.
( cd site && vercel deploy --prod >/dev/null )
echo "✓ site deployed"

echo ""
echo "Done. Users see the update banner within 6 hours, or immediately via"
echo "the app menu → Güncellemeleri Denetle."
