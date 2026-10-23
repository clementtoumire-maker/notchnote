#!/bin/bash
# Double-click to build, install and start NotchNote.
cd "$(dirname "$0")" && ./scripts/install.sh
echo; read -n 1 -s -r -p "Press any key to close"
