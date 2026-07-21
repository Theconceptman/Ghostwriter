#!/bin/bash
# Generates Resources/AppIcon.icns from a rendered ghost glyph (AppKit draws it,
# sips resizes it, iconutil packs it — no external design tools needed).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Resources
ICONSET=/tmp/gw_icon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
BASE=/tmp/gw_icon_1024.png

swift Scripts/gen_icon.swift "$BASE"

for px in 16 32 128 256 512; do
  sips -z $px $px "$BASE" --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  double=$((px * 2))
  sips -z $double $double "$BASE" --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
