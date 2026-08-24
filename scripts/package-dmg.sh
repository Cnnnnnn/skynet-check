#!/bin/bash

# Builds a local DMG (app + /Applications symlink) from the packaged app.
# No signing or notarization required — for team distribution with
# Developer ID signing use package-team-release.sh instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
APP_BUNDLE="$REPO_ROOT/build/Skynet Login Monitor.app"
VERSION_INFO="$("$SCRIPT_DIR/app-version.sh")"
VERSION="${VERSION_INFO%% *}"
DMG_PATH="$REPO_ROOT/build/Skynet Login Monitor-$VERSION.dmg"
TEMP_ROOT="$(/usr/bin/mktemp -d '/tmp/skynet-dmg.XXXXXXX')"

cleanup() {
    /bin/rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "App bundle not found; run scripts/package-app.sh first" >&2
    exit 1
fi

/usr/bin/ditto "$APP_BUNDLE" "$TEMP_ROOT/Skynet Login Monitor.app"
/bin/ln -s /Applications "$TEMP_ROOT/Applications"

/usr/bin/hdiutil create \
    -volname "Skynet Login Monitor" \
    -srcfolder "$TEMP_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

/usr/bin/hdiutil verify "$DMG_PATH"
echo "DMG: $DMG_PATH"
