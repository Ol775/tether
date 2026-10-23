#!/bin/bash
# Build build/Tether.app: release binary + bundled adb, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/fetch-platform-tools.sh
swift build -c release --product Tether
BIN=$(swift build -c release --show-bin-path)
APP=build/Tether.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Tether" "$APP/Contents/MacOS/Tether"
cp -R "$BIN"/Tether_TetherCore.bundle "$APP/Contents/Resources/" 2>/dev/null || true
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp vendor/platform-tools/adb "$APP/Contents/Resources/adb"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Tether</string>
<key>CFBundleIdentifier</key><string>io.github.ol775.tether</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>Tether</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Tether finds and talks to devices on your network.</string>
<key>NSBonjourServices</key><array><string>_adb-tls-connect._tcp</string><string>_adb-tls-pairing._tcp</string></array>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"
echo "built $APP"
