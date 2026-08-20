#!/bin/bash

# Prints "<marketing-version> <build-number>" for the app bundle.
# The version comes from the newest reachable v* git tag; the build number
# is the total commit count. Release by tagging, e.g. git tag v0.2.0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

VERSION="$(cd "$REPO_ROOT" && /usr/bin/git describe --tags --match 'v*' --abbrev=0 2>/dev/null | /usr/bin/sed 's/^v//')"
if [[ -z "$VERSION" ]]; then
    echo "error: no v* git tag found; create one first, e.g. git tag v0.2.0" >&2
    exit 1
fi

COMMIT_COUNT="$(cd "$REPO_ROOT" && /usr/bin/git rev-list --count HEAD 2>/dev/null || echo 0)"

echo "$VERSION $COMMIT_COUNT"
