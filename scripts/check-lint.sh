#!/bin/sh
# Fails on any SwiftLint warning or error. The paths and rules are in .swiftlint.yml.
# Install with: brew install swiftlint
set -eu
cd "$(dirname "$0")/.."
if ! command -v swiftlint > /dev/null; then
  echo "FAIL: swiftlint not found. Install it with: brew install swiftlint" >&2
  exit 1
fi
swiftlint lint --strict --quiet
