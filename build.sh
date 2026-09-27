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
# Desktop and Documents may be managed by a sync provider that recreates
# FinderInfo after xattr -cr. Keep signed bundles in a local app-support folder.
OUTPUT_DIR="${BDMENU_OUTPUT_DIR:-$HOME/Library/Application Support/BDMenu/Build}"
mkdir -p "$OUTPUT_DIR"
STAGE=$(mktemp -d "$OUTPUT_DIR/stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/BDMenu.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BDMenu" "$APP/Contents/MacOS/BDMenu"
cp bin/m1ddc bin/displayplacer "$APP/Contents/Resources/"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
# Finder metadata/resource forks inherited from local files are rejected by
# codesign. Clean only the new staging bundle before any signatures are made.
xattr -cr "$APP"
if xattr -p com.apple.FinderInfo "$APP" >/dev/null 2>&1; then
  echo "FinderInfo persists on the staging app at $APP; use a local BDMENU_OUTPUT_DIR outside synced folders." >&2
  exit 1
fi
# Sign nested executables explicitly, then seal the bundle. Never use --deep to sign.
for HELPER in m1ddc displayplacer; do
  codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/$HELPER"
done
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
# Keep the previous app until the staged build is signed and verified.
rm -rf "$OUTPUT_DIR/BDMenu.previous.app"
if [ -d "$OUTPUT_DIR/BDMenu.app" ]; then mv "$OUTPUT_DIR/BDMenu.app" "$OUTPUT_DIR/BDMenu.previous.app"; fi
if ! mv "$APP" "$OUTPUT_DIR/BDMenu.app"; then
  if [ -d "$OUTPUT_DIR/BDMenu.previous.app" ]; then mv "$OUTPUT_DIR/BDMenu.previous.app" "$OUTPUT_DIR/BDMenu.app"; fi
  exit 1
fi
if ! $ADHOC; then
  # Persist the chosen identity outside .build so a clean build does not change it.
  printf '%s\n' "$IDENTITY" > .signing-identity
  chmod 600 .signing-identity
fi
codesign -d -r- "$OUTPUT_DIR/BDMenu.app" 2>&1
echo "Built: $OUTPUT_DIR/BDMenu.app"
echo "Install/update at a stable path with ./install.sh"
