#!/bin/bash
# Build the native macOS icon and README logo from the full-resolution PNG master.
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_TMP=$(mktemp -d)
trap 'rm -rf "$ICON_TMP"' EXIT
ICON_SET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICON_SET"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" assets/icon.png --out "$ICON_SET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -s format png -z "$retina" "$retina" assets/icon.png --out "$ICON_SET/icon_${size}x${size}@2x.png" >/dev/null
done
swift scripts/assemble-icon.swift "$ICON_SET" assets/AppIcon.icns
sips -s format png -z 512 512 assets/icon.png --out docs/images/logo.png >/dev/null
