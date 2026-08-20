#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
BUILD_ROOT="$REPO_ROOT/build"
APP_BUNDLE="$BUILD_ROOT/Skynet Login Monitor.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
INFO_PLIST="$REPO_ROOT/Packaging/Info.plist"
SIGNING_IDENTITY="${SKYNET_SIGNING_IDENTITY:--}"

case "$APP_BUNDLE" in
    "$REPO_ROOT"/build/*.app) ;;
    *)
        echo "Refusing unsafe app bundle target: $APP_BUNDLE" >&2
        exit 1
        ;;
esac

cd "$REPO_ROOT"
/usr/bin/xcrun swift build -c release --product SkynetLoginMonitor
BIN_DIR="$(/usr/bin/xcrun swift build -c release --show-bin-path)"
EXECUTABLE="$BIN_DIR/SkynetLoginMonitor"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Release executable not found: $EXECUTABLE" >&2
    exit 1
fi
if [[ ! -f "$INFO_PLIST" ]]; then
    echo "Info.plist not found: $INFO_PLIST" >&2
    exit 1
fi

if [[ -e "$APP_BUNDLE" ]]; then
    /bin/rm -rf -- "$APP_BUNDLE"
fi
/bin/mkdir -p "$MACOS_DIR"
/bin/cp "$EXECUTABLE" "$MACOS_DIR/SkynetLoginMonitor"
/bin/cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"

/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist"
/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "Packaged: $APP_BUNDLE"
