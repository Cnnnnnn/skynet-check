#!/bin/bash

set -euo pipefail

: "${SKYNET_SIGNING_IDENTITY:?Set SKYNET_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${SKYNET_NOTARY_PROFILE:?Set SKYNET_NOTARY_PROFILE to an existing notarytool keychain profile}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
APP_BUNDLE="$REPO_ROOT/build/Skynet Login Monitor.app"
VERSION_INFO="$("$SCRIPT_DIR/app-version.sh")"
VERSION="${VERSION_INFO%% *}"
DMG_PATH="$REPO_ROOT/build/Skynet Login Monitor-$VERSION.dmg"
TEMP_ROOT="$(/usr/bin/mktemp -d '/tmp/skynet-team-release.XXXXXX')"

cleanup() {
    /bin/rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT

SKYNET_SIGNING_IDENTITY="$SKYNET_SIGNING_IDENTITY" \
    "$SCRIPT_DIR/package-app.sh"

/usr/bin/ditto "$APP_BUNDLE" "$TEMP_ROOT/Skynet Login Monitor.app"
/bin/ln -s /Applications "$TEMP_ROOT/Applications"
/usr/bin/hdiutil create \
    -volname "Skynet Login Monitor" \
    -srcfolder "$TEMP_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

/usr/bin/codesign --force --sign "$SKYNET_SIGNING_IDENTITY" "$DMG_PATH"
/usr/bin/xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$SKYNET_NOTARY_PROFILE" \
    --wait
/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"
/usr/bin/hdiutil verify "$DMG_PATH"

echo "Team release: $DMG_PATH"
