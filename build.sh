#!/bin/bash
# Сборка Marchel Records.app и установщика Marchel-Records.dmg (запускать на macOS 13+ с Xcode или Command Line Tools)
set -euo pipefail
cd "$(dirname "$0")"
APP_NAME="Marchel Records"
VERSION="${VERSION:-1.0}"
BUILD="${BUILD:-1}"
rm -rf build dist
mkdir -p build dist
for arch in arm64 x86_64; do
  echo "→ Компиляция $arch"
  swiftc -O -swift-version 5 -parse-as-library \
    -target "${arch}-apple-macos13.0" \
    Sources/*.swift -o "build/MarchelRecords-$arch" \
    -framework SwiftUI -framework AppKit -framework ScreenCaptureKit \
    -framework AVFoundation -framework CoreMedia -framework Carbon
done
APP="build/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create build/MarchelRecords-arm64 build/MarchelRecords-x86_64 -output "$APP/Contents/MacOS/MarchelRecords"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Info.plist > "$APP/Contents/Info.plist"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP"

echo "→ Установщик"
STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "dist/Marchel-Records.dmg"
echo "Готово: dist/Marchel-Records.dmg"
