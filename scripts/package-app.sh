#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
BUILD_ROOT="$REPO_ROOT/build"
APP_BUNDLE="$BUILD_ROOT/Skynet Login Monitor.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCE_DIR="$CONTENTS_DIR/Resources"
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
/usr/bin/xcrun swift build -c release \
    --triple arm64-apple-macosx13.0 \
    --product SkynetLoginMonitor
/usr/bin/xcrun swift build -c release \
    --triple x86_64-apple-macosx13.0 \
    --product SkynetLoginMonitor

ARM_BIN_DIR="$(/usr/bin/xcrun swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)"
INTEL_BIN_DIR="$(/usr/bin/xcrun swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)"
ARM_BINARY="$ARM_BIN_DIR/SkynetLoginMonitor"
INTEL_BINARY="$INTEL_BIN_DIR/SkynetLoginMonitor"
EXECUTABLE="$BUILD_ROOT/SkynetLoginMonitor-universal"

if [[ ! -x "$ARM_BINARY" || ! -x "$INTEL_BINARY" ]]; then
    echo "Release executables not found for both architectures" >&2
    exit 1
fi
if [[ ! -f "$INFO_PLIST" ]]; then
    echo "Info.plist not found: $INFO_PLIST" >&2
    exit 1
fi

"$SCRIPT_DIR/build-app-icon.sh"
ICON_FILE="$BUILD_ROOT/AppIcon.icns"
if [[ ! -f "$ICON_FILE" ]]; then
    echo "App icon not found: $ICON_FILE" >&2
    exit 1
fi

if [[ -e "$APP_BUNDLE" ]]; then
    /bin/rm -rf -- "$APP_BUNDLE"
fi
/usr/bin/lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$EXECUTABLE"
/bin/mkdir -p "$MACOS_DIR" "$RESOURCE_DIR"
/bin/cp "$EXECUTABLE" "$MACOS_DIR/SkynetLoginMonitor"
/bin/cp "$ICON_FILE" "$RESOURCE_DIR/AppIcon.icns"
/bin/cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"

/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist"
/usr/bin/lipo -info "$MACOS_DIR/SkynetLoginMonitor"
/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "Packaged: $APP_BUNDLE"
