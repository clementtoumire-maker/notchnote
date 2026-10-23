#!/bin/bash
# Compiles MarkdownCodec.swift with a tiny test driver and runs it. Needs only swiftc.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -o build/selftest NotchNote/Model/MarkdownCodec.swift tests/main.swift
./build/selftest
