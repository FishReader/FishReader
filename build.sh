#!/bin/bash
# Baut FishReader.app nach ./build/ (benötigt nur die Xcode Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/FishReader.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/FishReader"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FishReader"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swiftc -O -o build/make_icon scripts/make_icon/main.swift Sources/FishReader/LogoGeometry.swift
build/make_icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FishReader</string>
    <key>CFBundleDisplayName</key><string>FishReader</string>
    <key>CFBundleIdentifier</key><string>local.vorleser.app</string>
    <key>CFBundleExecutable</key><string>FishReader</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Fertig: $APP"
