#!/bin/bash

set -euo pipefail

FIX_PERMISSIONS=false
if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [--fix-permissions]" >&2
    exit 2
fi
if [[ $# -eq 1 ]]; then
    if [[ "$1" != "--fix-permissions" ]]; then
        echo "Unknown option: $1" >&2
        exit 2
    fi
    FIX_PERMISSIONS=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SOURCE_APP="$REPO_ROOT/build/Skynet Login Monitor.app"
DESTINATION_APP="/Applications/Skynet Login Monitor.app"
SKYNET_MONITOR_USER_NAME="$(/usr/bin/id -un)"
SKYNET_MONITOR_HOME_DIR="$(/usr/bin/dscl . -read "/Users/$SKYNET_MONITOR_USER_NAME" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
SKYNET_MONITOR_CONFIG_DIR="${SKYNET_MONITOR_CONFIG_DIR:-$SKYNET_MONITOR_HOME_DIR/.skynet-cli}"

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Packaged app not found. Run scripts/package-app.sh first." >&2
    exit 1
fi
if [[ ! -t 0 ]]; then
    echo "Installation requires an interactive terminal." >&2
    exit 1
fi

echo "Source:      $SOURCE_APP"
echo "Destination: $DESTINATION_APP"
if [[ "$FIX_PERMISSIONS" == true ]]; then
    echo "Skynet permissions will be restricted under: $SKYNET_MONITOR_CONFIG_DIR"
else
    echo "Skynet permissions will only be inspected."
fi
read -r -p "Continue? [y/N] " REPLY
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

/usr/bin/ditto "$SOURCE_APP" "$DESTINATION_APP"

if [[ -d "$SKYNET_MONITOR_CONFIG_DIR" ]]; then
    echo "Current modes:"
    /usr/bin/stat -f "%Sp %N" "$SKYNET_MONITOR_CONFIG_DIR"
    for SENSITIVE_FILE in session.json config.json; do
        if [[ -f "$SKYNET_MONITOR_CONFIG_DIR/$SENSITIVE_FILE" ]]; then
            /usr/bin/stat -f "%Sp %N" "$SKYNET_MONITOR_CONFIG_DIR/$SENSITIVE_FILE"
        fi
    done

    if [[ "$FIX_PERMISSIONS" == true ]]; then
        /bin/chmod 700 "$SKYNET_MONITOR_CONFIG_DIR"
        for SENSITIVE_FILE in session.json config.json; do
            if [[ -f "$SKYNET_MONITOR_CONFIG_DIR/$SENSITIVE_FILE" ]]; then
                /bin/chmod 600 "$SKYNET_MONITOR_CONFIG_DIR/$SENSITIVE_FILE"
            fi
        done
        echo "Skynet permissions updated."
    else
        echo "To repair broad permissions, rerun with --fix-permissions."
    fi
else
    echo "Skynet config directory does not exist; no permissions inspected."
fi

echo "Installed: $DESTINATION_APP"
