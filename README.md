# Vital Courier

An iOS app that exports Apple Health data to a folder you pick, such as one in iCloud Drive or an Obsidian vault, and keeps the files up to date in the background after setup. It has no account and no server. The app is in English and Brazilian Portuguese, following the iPhone's language.

The app isn't released yet. It is heading to TestFlight first.

## What it exports

It exports the Apple Health data you allow, plus cycle data when Cycle tracking is on in Settings. Everything goes into a `Vital Courier` folder inside the folder you pick:

```
Vital Courier/
  README.md                     says the app owns this folder and overwrites edits
  json/<type>/<YYYY-MM>.json    every raw sample of one type for one month
  daily/<YYYY-MM-DD>.md         one note per day, with that day's values as properties
```

The JSON is an export of each stored sample, with its source name, device name and metadata (metadata values are saved as text). The daily notes hold that day's values in YAML frontmatter, always metric, so Obsidian Bases or Dataview can query them. The keys are `date`, `vc_steps`, `vc_exercise_minutes`, `vc_resting_hr_bpm`, `vc_respiratory_rate`, `vc_respiratory_rate_min`, `vc_respiratory_rate_max`, `vc_glucose_mg_dl`, `vc_glucose_mg_dl_min`, `vc_glucose_mg_dl_max`, `vc_sleep_hours`, `vc_sleep_deep_hours`, `vc_sleep_rem_hours`, `vc_sleep_source`, `vc_weight_kg`, `vc_menstrual_flow`, `vc_period_start`, `vc_spotting` and `vc_schema`. `date` and `vc_schema` are always there; a health key is left out when the day has no value for it. The two cycle flags are written only when true. The file names match Obsidian's daily notes.

## When it runs

| Trigger | What it does |
|---|---|
| Observer wake | HealthKit tells the app new data arrived. The app reads it and writes the changed days. |
| App open | Reads new data and checks the last 30 days against HealthKit for deletions. |
| Background refresh | The same as App open, when iOS gives the app background time. HealthKit can't be read while the phone is locked, so a locked run only writes days already saved. |
| Export now | An App Intent for Shortcuts. Writes days already saved, without reading HealthKit, so it works on a locked phone. |
| Rebuild all | In Settings. Rereads every enabled data type and rewrites every day and month the app knows about. The phone must be unlocked for the full rebuild. While it is locked, the HealthKit read is skipped, only the saved monthly JSON files are rewritten, and the daily notes wait until the phone is unlocked. |

The History screen lists every run with its trigger and result.

## Privacy

Vital Courier makes no network connections of its own and sends Health data nowhere. It reads HealthKit, keeps a local copy in an SQLite database on the phone (excluded from backups), and writes files only to the folder you picked. If that folder is in iCloud Drive or another synced location, the system or that provider syncs the files, not the app. The only link out is the privacy policy link in Settings, which the system browser opens: [vitalcourier.app/privacy](https://vitalcourier.app/privacy).

## Requirements

- iOS 18 or later.
- Xcode 27. The project uses Swift 6 with complete strict concurrency.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). `VitalCourier.xcodeproj` isn't committed; it is generated from `project.yml`.

## Building and testing

Run these from the repo root:

```bash
swift test --package-path VitalCourierCore
scripts/generate-project.sh
xcodebuild -project VitalCourier.xcodeproj -scheme VitalCourier \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/DerivedData -quiet build
xcodebuild test -project VitalCourier.xcodeproj -scheme VitalCourier \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/DerivedData -only-testing:VitalCourierTests -quiet
scripts/check-translations.sh build/DerivedData
```

`check-translations.sh` fails when a String Catalog entry has no Brazilian Portuguese translation, or when the code uses a string the catalog doesn't list. `scripts/check-migrations.sh` fails when a database migration that is already on `main` was edited, removed or reordered.

`project.yml` sets the author's development team, so building to a real iPhone needs your own team and bundle ID.

## Project layout

```
App/                 The SwiftUI app: screens, models, triggers and the String Catalogs
AppTests/            Unit tests for the app layer (target VitalCourierTests)
VitalCourierCore/    Swift package with the export logic
  VitalCourierCore       Reading, storing (GRDB), and writing the JSON and Markdown files
  VitalCourierHealthKit  The HealthKit reader
Config/              Info.plist and the entitlements (HealthKit with background delivery)
scripts/             Project generation and the translation and migration checks
project.yml          XcodeGen spec
```

## Contributing

Bug reports and feature requests go through the issue forms. Issues are public, so don't paste health data into one. Pull requests follow `.github/pull_request_template.md`.

Database migrations on `main` are frozen. Change the schema by adding a new migration with a new ID.

## License

The source code is MIT licensed. See [LICENSE](LICENSE).

### Reserved artwork

The MIT license does not grant rights to the Vital Courier app artwork below. Copyright 2026 Kleber Kihara, all rights reserved:

- `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (the existing icon path, now holding the Circuit icon)
- `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png`
- `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png`
- `App/Resources/Assets.xcassets/LaunchCircuit.imageset/LaunchCircuit@2x.png`
- `App/Resources/Assets.xcassets/LaunchCircuit.imageset/LaunchCircuit@3x.png`
- `App/Resources/Assets.xcassets/LaunchCircuit.imageset/LaunchCircuit-Dark@2x.png`
- `App/Resources/Assets.xcassets/LaunchCircuit.imageset/LaunchCircuit-Dark@3x.png`
