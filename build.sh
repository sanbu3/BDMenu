#!/bin/bash
set -e
cd "$(dirname "$0")"
./make_icon.sh
swift build -c release
APP="build/BDMenu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BDMenu "$APP/Contents/MacOS/BDMenu"
cp bin/m1ddc bin/displayplacer "$APP/Contents/Resources/"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"
echo "built: $APP"
