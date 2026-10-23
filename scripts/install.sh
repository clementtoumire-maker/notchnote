#!/bin/bash
# One command: build (Release), install into /Applications, launch, and keep it running in the background.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=""
if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  echo "Building with Xcode..."
  CONFIG=Release ./scripts/build.sh
  SRC="build/Build/Products/Release/NotchNote.app"
elif command -v swiftc >/dev/null 2>&1 && xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
  echo "Xcode not found. Building with the Command Line Tools only..."
  ./scripts/build-fallback.sh
  SRC="build/fallback/NotchNote.app"
else
  echo "Neither Xcode nor the Command Line Tools were found." >&2
  echo "Install the small one by running:  xcode-select --install   (then run this again)" >&2
  exit 1
fi
DEST="/Applications/NotchNote.app"

osascript -e 'tell application "NotchNote" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x NotchNote >/dev/null 2>&1 || true
rm -rf "$DEST"
ditto "$SRC" "$DEST"
xattr -cr "$DEST"
codesign --force --deep --sign - "$DEST"      # ad-hoc re-sign after the copy
open "$DEST"
echo
echo "Installed and started: $DEST"
echo "It runs in the background (no Dock icon) and starts at every login."
echo "If macOS asks, allow it under System Settings > General > Login Items."
echo "Quit it from the menu bar icon. Remove it with: make uninstall"
