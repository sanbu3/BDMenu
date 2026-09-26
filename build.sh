#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -s)" != Darwin ]; then
  echo "BDMenu must be built on macOS with Xcode Command Line Tools." >&2
  exit 1
fi
ADHOC=false
case "${1:-}" in
  --adhoc) ADHOC=true ;;
  '') ;;
  *) echo "Usage: ./build.sh [--adhoc]" >&2; exit 2 ;;
esac
IDENTITY="${CODE_SIGN_IDENTITY:-}"
if $ADHOC; then
  IDENTITY=-
  echo "WARNING: ad-hoc test build; Accessibility permission may be lost after rebuilding." >&2
else
  if [ -z "$IDENTITY" ] && [ -f .signing-identity ]; then IDENTITY=$(cat .signing-identity); fi
  if [ -z "$IDENTITY" ]; then
    IDENTITIES=$(security find-identity -v -p codesigning)
    CANDIDATES=$(printf '%s\n' "$IDENTITIES" | awk '/"Apple Development:/ {print $2}')
    if [ -z "$CANDIDATES" ]; then
      CANDIDATES=$(printf '%s\n' "$IDENTITIES" | awk '/"Developer ID Application:/ {print $2}')
    fi
    COUNT=$(printf '%s\n' "$CANDIDATES" | awk 'NF {n++} END {print n+0}')
    if [ "$COUNT" != 1 ]; then
      echo "A stable signing identity is required. Found $COUNT matching identities." >&2
      echo "In Xcode > Settings > Accounts > Manage Certificates, create Apple Development." >&2
      echo "Then run: CODE_SIGN_IDENTITY='<identity SHA-1>' ./build.sh" >&2
      echo "Use security find-identity -v -p codesigning to list identities." >&2
      echo "For disposable builds only: ./build.sh --adhoc" >&2
      exit 1
    fi
    IDENTITY=$CANDIDATES
  fi
  if [ "$IDENTITY" = - ]; then echo "Use --adhoc explicitly for an ad-hoc build." >&2; exit 2; fi
fi

mkdir -p build
./make_icon.sh
ARCH="${BDMENU_ARCH:-arm64}"
swift build -c release --arch "$ARCH"
BIN_DIR=$(swift build -c release --arch "$ARCH" --show-bin-path)
STAGE=$(mktemp -d "$PWD/build/stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/BDMenu.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BDMenu" "$APP/Contents/MacOS/BDMenu"
cp bin/m1ddc bin/displayplacer "$APP/Contents/Resources/"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
# Sign nested executables explicitly, then seal the bundle. Never use --deep to sign.
for HELPER in m1ddc displayplacer; do
  codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/$HELPER"
done
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
# Keep the previous app until the staged build is signed and verified.
rm -rf build/BDMenu.previous.app
if [ -d build/BDMenu.app ]; then mv build/BDMenu.app build/BDMenu.previous.app; fi
if ! mv "$APP" build/BDMenu.app; then
  if [ -d build/BDMenu.previous.app ]; then mv build/BDMenu.previous.app build/BDMenu.app; fi
  exit 1
fi
if ! $ADHOC; then
  # Persist the chosen identity outside .build so a clean build does not change it.
  printf '%s\n' "$IDENTITY" > .signing-identity
  chmod 600 .signing-identity
fi
codesign -d -r- build/BDMenu.app 2>&1
echo "Built: $PWD/build/BDMenu.app"
echo "Install/update at a stable path with ./install.sh"
