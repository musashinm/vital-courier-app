---
name: verify
description: Build and test Vital Courier end to end (VitalCourierCore package tests, Xcode project regeneration, a simulator build of the app, and the app's unit tests, plus the translation and migration checks). Use before claiming a task is done, before committing, and before the final review.
allowed-tools:
  - Bash(scripts/verify.sh)
  - Bash(VERIFY_DESTINATION=* scripts/verify.sh)
  - Bash(xcrun simctl list devices available)
---

Run `scripts/verify.sh` from the repo root. It runs these six steps in order and stops at the first failure:

1. Package tests
2. Generate project
3. Simulator build
4. App tests
5. Translations
6. Migrations

If the iPhone 18 Pro destination doesn't exist, run `xcrun simctl list devices available`, pick an available iPhone, rerun with `VERIFY_DESTINATION='platform=iOS Simulator,name=<device>' scripts/verify.sh`, and say which one you used.

Report each step as passed or failed, with its time. For a failure, quote the first error lines verbatim (file:line and message) and don't paraphrase them. Don't claim success for a step you didn't run.
