#!/bin/bash
# Собирает Sticker.app и Sticker.dmg в папку dist/ рядом со скриптом.
set -e
cd "$(dirname "$0")"
OUT="$PWD/dist"
APP="$OUT/Sticker.app"
ICON_SRC="${1:-$PWD/icon.png}"

rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ компилирую под Apple Silicon и Intel"
swiftc -O -parse-as-library Sources/*.swift -o /tmp/sticker_arm64 \
  -framework SwiftUI -framework AppKit -framework CoreBluetooth \
  -target arm64-apple-macos13.0
swiftc -O -parse-as-library Sources/*.swift -o /tmp/sticker_x86 \
  -framework SwiftUI -framework AppKit -framework CoreBluetooth \
  -target x86_64-apple-macos13.0
lipo -create /tmp/sticker_arm64 /tmp/sticker_x86 -output "$APP/Contents/MacOS/Sticker"

if [ -f "$ICON_SRC" ]; then
  ICONSET=/tmp/Sticker.iconset
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for SZ in 16 32 128 256 512; do
    sips -z $SZ $SZ "$ICON_SRC" --out "$ICONSET/icon_${SZ}x${SZ}.png" >/dev/null
    sips -z $((SZ*2)) $((SZ*2)) "$ICON_SRC" --out "$ICONSET/icon_${SZ}x${SZ}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Sticker</string>
  <key>CFBundleDisplayName</key><string>Sticker</string>
  <key>CFBundleIdentifier</key><string>ca.yoff.sticker</string>
  <key>CFBundleExecutable</key><string>Sticker</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Image</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key>
    <array><string>public.image</string></array>
  </dict></array>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>To send labels to your Bluetooth thermal printer</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "✓ app: $APP"

STAGE=/tmp/sticker_stage
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Sticker" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT/Sticker.dmg"
echo "✓ dmg: $OUT/Sticker.dmg"
