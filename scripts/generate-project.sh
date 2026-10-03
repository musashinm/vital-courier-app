#!/bin/sh
# Generates VitalCourier.xcodeproj from project.yml. The project file is not committed.
set -eu
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found: install it with 'brew install xcodegen'" >&2
    exit 1
fi
xcodegen generate --quiet
