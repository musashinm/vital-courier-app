---
name: verify
description: Build and test Vital Courier end to end (a swift-format check, VitalCourierCore package tests, Xcode project regeneration, a simulator build of the app, and the app's unit tests, plus the translation and migration checks). Use before claiming a task is done, before committing, and before the final review.
allowed-tools:
  - Bash(scripts/verify.sh)
  - Bash(VERIFY_DESTINATION=* scripts/verify.sh)
  - Bash(xcrun simctl list devices available)
---

Run `scripts/verify.sh` from the repo root. It runs these seven steps in order and stops at the first failure:

1. Format
2. Package tests
3. Generate project
4. Simulator build
5. App tests
6. Translations
7. Migrations

If the iPhone 18 Pro destination doesn't exist, run `xcrun simctl list devices available`, pick an available iPhone, rerun with `VERIFY_DESTINATION='platform=iOS Simulator,name=<device>' scripts/verify.sh`, and say which one you used.

Report each step as passed or failed, with its time. For a failure, quote the first error lines verbatim (file:line and message) and don't paraphrase them. Don't claim success for a step you didn't run.
