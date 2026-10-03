---
name: verify
description: Build and test Vital Courier end to end (VitalCourierCore package tests, Xcode project regeneration, and a simulator build of the app). Use before claiming a task is done, before committing, and before the final review.
allowed-tools:
  - Bash(swift test *)
  - Bash(scripts/generate-project.sh)
  - Bash(xcodebuild *)
  - Bash(xcrun simctl list devices available)
---

Run these from the repo root, in order, and stop at the first failure.

1. Package tests:
   `swift test --package-path VitalCourierCore`
2. Regenerate the project (it's gitignored and built from `project.yml`):
   `scripts/generate-project.sh`
3. Build the app for the simulator:
   `xcodebuild -project VitalCourier.xcodeproj -scheme VitalCourier -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData -quiet build`

   If the destination doesn't exist, run `xcrun simctl list devices available`, pick an available iPhone, and say which one you used.

Report each step as passed or failed. For a failure, quote the first error lines verbatim (file:line and message) and don't paraphrase them. Don't claim success for a step you didn't run.
