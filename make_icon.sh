#!/bin/bash
set -e
cd "$(dirname "$0")"
swift make_icon.swift build/icon_1024.png
ICONSET=build/icon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16     build/icon_1024.png --out "$ICONSET/icon_16x16.png"       >/dev/null
sips -z 32 32     build/icon_1024.png --out "$ICONSET/icon_16x16@2x.png"    >/dev/null
sips -z 32 32     build/icon_1024.png --out "$ICONSET/icon_32x32.png"       >/dev/null
sips -z 64 64     build/icon_1024.png --out "$ICONSET/icon_32x32@2x.png"    >/dev/null
sips -z 128 128   build/icon_1024.png --out "$ICONSET/icon_128x128.png"     >/dev/null
sips -z 256 256   build/icon_1024.png --out "$ICONSET/icon_128x128@2x.png"  >/dev/null
sips -z 256 256   build/icon_1024.png --out "$ICONSET/icon_256x256.png"     >/dev/null
sips -z 512 512   build/icon_1024.png --out "$ICONSET/icon_256x256@2x.png"  >/dev/null
sips -z 512 512   build/icon_1024.png --out "$ICONSET/icon_512x512.png"     >/dev/null
cp build/icon_1024.png "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o build/AppIcon.icns
echo "icns done: build/AppIcon.icns"
