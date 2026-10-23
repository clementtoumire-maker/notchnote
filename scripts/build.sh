#!/bin/bash
# Build NotchNote.app with xcodebuild (ad-hoc "Sign to Run Locally" signature, no Apple Developer account).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-Release}"
xcodebuild \
  -project NotchNote.xcodeproj \
  -scheme NotchNote \
  -configuration "$CONFIG" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=NO \
  build
APP="build/Build/Products/$CONFIG/NotchNote.app"
echo
echo "Built: $(pwd)/$APP"
