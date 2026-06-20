#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "→ Building (release)…"
# Run the build through a pipe so its non-zero exit status propagates
# even under set -e (pipefail is on). Then double-check explicitly so
# silent successes that leave a stale binary in place still abort.
if ! swift build -c release; then
  echo "✗ Release build FAILED — see errors above. Not packaging."
  exit 1
fi

APP="build/YTMusic.app"
BIN_SRC=".build/release/YTMusicMac"

# Sanity: the binary must be NEWER than every source file. Otherwise SPM
# kept a stale one and we'd ship a phantom build. Bail loudly.
if [ ! -f "$BIN_SRC" ]; then
  echo "✗ $BIN_SRC missing — build didn't produce a binary."
  exit 1
fi
NEWER_SRC=$(find Sources -type f -newer "$BIN_SRC" -print -quit)
if [ -n "$NEWER_SRC" ]; then
  echo "✗ Stale binary: $NEWER_SRC is newer than $BIN_SRC."
  echo "   This usually means the previous compile errored but SPM kept"
  echo "   the last good binary. Refusing to package."
  exit 1
fi

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
