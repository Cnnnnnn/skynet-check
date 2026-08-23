#!/bin/bash

# Pre-commit check: lint + test. Install with:
#   git config core.hooksPath scripts/githooks

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

echo "==> swiftlint"
if command -v swiftlint >/dev/null 2>&1; then
    swiftlint --quiet || exit 1
else
    echo "warning: swiftlint not installed, skipping" >&2
fi

echo "==> swift test"
swift test --quiet 2>&1 | tail -n 5
