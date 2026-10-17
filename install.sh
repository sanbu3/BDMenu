#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${BDMENU_OUTPUT_DIR:-$HOME/Library/Application Support/BDMenu/Build}/BDMenu.app"
DEST="${BDMENU_INSTALL_DIR:-/Applications}"
[ -d "$APP" ] || { echo "Run ./build.sh first." >&2; exit 1; }
[ -d "$DEST" ] && [ -w "$DEST" ] || { echo "No write access to $DEST; set BDMENU_INSTALL_DIR to a writable Applications directory." >&2; exit 1; }
codesign --verify --deep --strict "$APP"
STAGE=$(mktemp -d "$DEST/.BDMenu-install.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/BDMenu.app"
codesign --verify --deep --strict "$STAGE/BDMenu.app"
if pgrep -x BDMenu >/dev/null; then
  osascript -e 'tell application id "com.local.BDMenu" to quit'
  for ((ATTEMPT=0; ATTEMPT<30; ATTEMPT++)); do
    pgrep -x BDMenu >/dev/null || break
    sleep 0.1
  done
  if pgrep -x BDMenu >/dev/null; then echo "Quit BDMenu before installing." >&2; exit 1; fi
fi
# Compare code identity before replacing an installed app.
if [ -d "$DEST/BDMenu.app" ]; then
  OLD_REQUIREMENT=$(codesign -d -r- "$DEST/BDMenu.app" 2>&1 | sed -n 's/^designated => //p')
  if [ -n "$OLD_REQUIREMENT" ] && ! codesign --verify -R "$OLD_REQUIREMENT" "$APP" 2>/dev/null; then
    echo "Signing identity changed: remove the old BDMenu entry in Accessibility, then authorize the installed app once." >&2
  fi
  mv "$DEST/BDMenu.app" "$STAGE/previous.app"
fi
if ! mv "$STAGE/BDMenu.app" "$DEST/BDMenu.app"; then
  if [ -d "$STAGE/previous.app" ]; then mv "$STAGE/previous.app" "$DEST/BDMenu.app"; fi
  exit 1
fi
open "$DEST/BDMenu.app"
echo "Installed: $DEST/BDMenu.app"
