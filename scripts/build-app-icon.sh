#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ASSET_ROOT="$REPO_ROOT/Assets"
BUILD_ROOT="$REPO_ROOT/build"
SOURCE_IMAGE="$ASSET_ROOT/AppIcon-source.png"
PROCESSED_IMAGE="$BUILD_ROOT/AppIcon-processed.png"
ICONSET="$BUILD_ROOT/AppIcon.iconset"
OUTPUT="$BUILD_ROOT/AppIcon.icns"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
    echo "Icon source not found: $SOURCE_IMAGE" >&2
    exit 1
fi

/bin/mkdir -p "$BUILD_ROOT"
/usr/bin/xcrun swift "$SCRIPT_DIR/prepare-app-icon.swift" \
    "$SOURCE_IMAGE" "$PROCESSED_IMAGE"
/bin/rm -rf -- "$ICONSET"
/bin/mkdir -p "$ICONSET"

/usr/bin/sips -z 16 16 "$PROCESSED_IMAGE" --out "$ICONSET/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32 "$PROCESSED_IMAGE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32 "$PROCESSED_IMAGE" --out "$ICONSET/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64 "$PROCESSED_IMAGE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128 "$PROCESSED_IMAGE" --out "$ICONSET/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256 "$PROCESSED_IMAGE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256 "$PROCESSED_IMAGE" --out "$ICONSET/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512 "$PROCESSED_IMAGE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512 "$PROCESSED_IMAGE" --out "$ICONSET/icon_512x512.png" >/dev/null
/usr/bin/sips -z 1024 1024 "$PROCESSED_IMAGE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

/usr/bin/iconutil --convert icns --output "$OUTPUT" "$ICONSET"
echo "Built icon: $OUTPUT"
