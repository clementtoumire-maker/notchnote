#!/bin/bash
# Fallback that needs only the Xcode Command Line Tools (no .xcodeproj): compiles with swiftc and
# assembles the .app by hand. Output: build/fallback/NotchNote.app
# Limitation: the "Add task" Shortcuts action is only registered by the Xcode build (it runs the
# App Intents metadata extractor); everything else works.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/fallback"
APP="$OUT/NotchNote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARCH="$(uname -m)"
swiftc -O -parse-as-library -swift-version 5 \
  -target "$ARCH-apple-macos15.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -o "$APP/Contents/MacOS/NotchNote" \
  $(find NotchNote -name '*.swift')
cp NotchNote/Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built: $(pwd)/$APP"
