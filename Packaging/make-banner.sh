#!/bin/bash
# Regenerates docs/banner.png (the README hero banner). Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs
swift Packaging/render-banner.swift docs/banner.png \
  "doc.on.clipboard" "5B7CFA" "2E4BD0" \
  "StackClip" "Clipboard history & append-copy for macOS"
