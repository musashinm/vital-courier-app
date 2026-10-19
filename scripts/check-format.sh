#!/bin/sh
# Fails when any Swift file doesn't match .swift-format. Fix with:
#   xcrun swift-format format --in-place --parallel --recursive App AppTests VitalCourierCore/Package.swift VitalCourierCore/Sources VitalCourierCore/Tests
set -eu
cd "$(dirname "$0")/.."
xcrun swift-format lint --strict --parallel --recursive \
  App AppTests VitalCourierCore/Package.swift VitalCourierCore/Sources VitalCourierCore/Tests
