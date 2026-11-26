#!/bin/bash
# Baut FishReader.app neu und packt sie in build/FishReader-<Version>.dmg –
# mit gestaltetem Fenster: Hintergrund, App links, Programme-Ordner rechts, Pfeil dazwischen.
# Beim ersten Mal fragt macOS, ob das Skript den Finder steuern darf (für das Fenster-Layout).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VOL="FishReader"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/FishReader.app/Contents/Info.plist)
STAGE="build/dmg"
RW="build/FishReader-rw.dmg"
DMG="build/FishReader-$VERSION.dmg"

# Ein noch eingehängtes gleichnamiges Volume würde das Layout stören
if [ -d "/Volumes/$VOL" ]; then hdiutil detach "/Volumes/$VOL" -force >/dev/null || true; fi
rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"

# Inhalt
ditto build/FishReader.app "$STAGE/FishReader.app"
ln -s /Applications "$STAGE/Applications"
cp build/FishReader.app/Contents/Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# Hintergrundbild (@1x + @2x in einer TIFF)
swiftc -O -o build/dmg_background scripts/dmg_background/main.swift
build/dmg_background build
tiffutil -cathidpicheck build/background.png build/background@2x.png -out "$STAGE/.background/background.tiff" 2>/dev/null
rm -f build/background.png build/background@2x.png

# Beschreibbares Image anlegen und einhängen
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size 20m -ov "$RW" >/dev/null
DEVICE=$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT="/Volumes/$VOL"
SetFile -a C "$MOUNT"   # eigenes Volume-Icon aktivieren

# Fenster gestalten
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "FishReader.app" of container window to {170, 200}
        set position of item "Applications" of container window to {490, 200}
        -- Versteckte Dateien aus dem sichtbaren Bereich schieben (falls im Finder eingeblendet)
        repeat with hiddenName in {".background", ".fseventsd", ".VolumeIcon.icns", ".DS_Store", ".Trashes"}
            try
                set position of item (hiddenName as text) of container window to {100, 900}
            end try
        end repeat
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Abschließen: schreibgeschützt und komprimiert
chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach "$DEVICE" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf "$STAGE" "$RW"

echo "Fertig: $DMG ($(du -h "$DMG" | cut -f1))"
