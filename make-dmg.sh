#!/bin/bash
# Собирает оформленный установщик: фон, крупные значки, стрелка к «Программам».
set -e
cd "$(dirname "$0")"
OUT="$PWD/dist"
APP="$OUT/Sticker.app"
BG="$PWD/dmg-background.png"
VOL="Sticker"
TMP="$OUT/rw.dmg"
MNT="/Volumes/$VOL"

[ -d "$APP" ] || { echo "сначала ./build.sh"; exit 1; }
rm -f "$TMP" "$OUT/Sticker.dmg"
hdiutil detach "$MNT" >/dev/null 2>&1 || true

echo "→ готовлю образ"
hdiutil create -srcfolder "$APP" -volname "$VOL" -fs HFS+ \
  -format UDRW -size 60m -quiet "$TMP"
hdiutil attach "$TMP" -quiet -nobrowse -noautoopen
sleep 1

ln -s /Applications "$MNT/Applications"
mkdir -p "$MNT/.background"
[ -f "$BG" ] && cp "$BG" "$MNT/.background/background.png"

echo "→ раскладываю окно"
osascript <<APPLESCRIPT || echo "   (Finder недоступен — соберу простой образ)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 840, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "Sticker.app" of container window to {180, 245}
    set position of item "Applications" of container window to {460, 245}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync; sleep 1
hdiutil detach "$MNT" -quiet || hdiutil detach "$MNT" -force -quiet
echo "→ сжимаю"
hdiutil convert "$TMP" -format UDZO -imagekey zlib-level=9 -o "$OUT/Sticker.dmg" -quiet
rm -f "$TMP"
echo "✓ установщик: $OUT/Sticker.dmg"
