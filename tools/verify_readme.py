#!/usr/bin/env python3
import os, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
t = open(os.path.join(root, "README.md"), encoding="utf-8").read()
need = ["xcodebuild", "Sign to Run Locally", "make install", "/Applications", "System Settings",
        "Not verified", "CloudKit", "Stage 1", "Stage 6", "build-fallback"]
missing = [n for n in need if n not in t]
if missing:
    print("README missing:", missing); sys.exit(1)
print("readme verification passed")
