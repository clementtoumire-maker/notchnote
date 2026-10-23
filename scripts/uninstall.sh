#!/bin/bash
# Quit and remove NotchNote. Your notes in ~/Library/Application Support/NotchNote are kept.
set -u
osascript -e 'tell application "NotchNote" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x NotchNote >/dev/null 2>&1 || true
rm -rf /Applications/NotchNote.app
echo "Removed /Applications/NotchNote.app (notes were not touched)."
echo "If it still shows in System Settings > General > Login Items, remove it there."
