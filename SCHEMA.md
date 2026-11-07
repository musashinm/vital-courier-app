# Vital Courier export schema

This describes every file Vital Courier writes into the `Vital Courier/` folder you pick. If a script, Obsidian Bases, Dataview or a spreadsheet reads the export, this is the contract.

## 1. Versioning and compatibility

Version: 1

The version is `vc_schema` in each daily note and `schemaVersion` in each JSON month file. Both always carry the same number. It covers the Markdown and JSON formats only.

CSV is versioned on its own terms. A CSV file carries no version, and it doesn't follow the number above. The header row is the contract. A breaking CSV change goes to a new folder, `csv-v2/`, beside `csv/`, so a file in `csv/` never changes meaning. Breaking means adding, removing, renaming or reordering a column, changing what a column means, or changing the timestamp format or zone rules. Non-breaking CSV changes (none are planned) would keep the header exactly as it is.

Not breaking, no version bump (Markdown and JSON):

- A new optional frontmatter key.
- A new JSON field: top level, inside `period`, or inside a sample.
- A new data type: a new folder name, a new JSON `type` or a new `unit` value.
- A new category value string, including a name for a raw value that used to come out as `unknown(<n>)`.
- A new key inside `metadata`.
- New text in the export `README.md`.

Breaking, bumps the version (Markdown and JSON):

- Renaming or removing a key or a JSON field.
- Changing a key's unit, precision or rounding.
- Changing what a value means (blood oxygen going from a fraction to a percent, say).
- Changing a path or a file name pattern.
- Changing the timestamp format or the zone rule.
- Changing a documented category value string (the named ones in section 6).

Every bump is listed in section 8 with its date and app version. So is a new `csv-v2/` folder.

Readers should ignore keys and JSON fields they don't know. They should also treat `unknown(<n>)` as a value a later version may name.

## 2. Folder layout and file names

Everything sits under `Vital Courier/` in the folder you picked:

- `README.md`
- `json/<folder>/<YYYY-MM>.json`
- `csv/<folder>/<YYYY-MM>.csv`
- `daily/<YYYY-MM-DD>.md` (the same file name Obsidian's daily notes use)

Only the formats you turned on are written. Turning one off deletes nothing.

### Which day or month a sample lands in

- A sample's zone is the one in its HealthKit metadata (`HKMetadataKeyTimeZone`) when that is present and valid. Otherwise it's the phone's zone at the moment the app first indexes the sample, and that stays frozen.
- A JSON or CSV sample goes in the month of its `start`, in that sample's zone.
- Weight, menstrual flow and spotting count on the day of the sample's `start`, in that sample's zone.
- Sleep belongs to the wake day: the day the last asleep sample of the night ends, in that sample's zone.
- Eight types come from HealthKit's daily statistics instead: steps, exercise minutes, resting heart rate, walking heart rate average, heart rate, respiratory rate, blood glucose and blood oxygen. They cover local midnight to midnight in the phone's zone at export time.

### Types

One row per type. The `type` column is the JSON `type` field, `folder` is the folder name under `json/` and `csv/`, and `unit` is the JSON and CSV `unit`.

| `type` | `folder` | `unit` |
|---|---|---|
| `steps` | `steps` | `count` |
| `exerciseMinutes` | `exercise-minutes` | `s` |
| `restingHeartRate` | `resting-heart-rate` | `count/s` |
| `walkingHeartRateAverage` | `walking-heart-rate-average` | `count/s` |
| `heartRate` | `heart-rate` | `count/s` |
| `respiratoryRate` | `respiratory-rate` | `count/s` |
| `bloodGlucose` | `blood-glucose` | `g/L` |
| `bloodOxygen` | `blood-oxygen` | `%` (HealthKit's percent unit, a 0 to 1 fraction) |
| `sleep` | `sleep` | `category` |
| `weight` | `weight` | `kg` |
| `menstrualFlow` | `menstrual-flow` | `category` |
| `spotting` | `spotting` | `category` |

Menstrual flow and spotting are only exported while Cycle tracking is on.

## 3. Daily Markdown note

The note is YAML frontmatter and nothing else, always metric. Decimals use `.` whatever the device language is. `date` and `vc_schema` are always there. A health key is left out when the day has no value for it. The two cycle flags show up only when true.

Keys, in file order:

| Key | Unit | Format |
|---|---|---|
| `date` | `YYYY-MM-DD` | always |
| `vc_steps` | steps | integer, truncated toward zero |
| `vc_exercise_minutes` | minutes | integer, truncated toward zero |
| `vc_resting_hr_bpm` | bpm | one decimal |
| `vc_walking_hr_avg` | bpm | one decimal |
| `vc_hr_avg` | bpm | whole number, rounded |
| `vc_hr_min` | bpm | whole number, rounded |
| `vc_hr_max` | bpm | whole number, rounded |
| `vc_respiratory_rate` | breaths/min | one decimal |
| `vc_respiratory_rate_min` | breaths/min | one decimal |
| `vc_respiratory_rate_max` | breaths/min | one decimal |
| `vc_glucose_mg_dl` | mg/dL | whole number, rounded |
| `vc_glucose_mg_dl_min` | mg/dL | whole number, rounded |
| `vc_glucose_mg_dl_max` | mg/dL | whole number, rounded |
| `vc_blood_oxygen_pct_min` | percent, 0 to 100 | whole number, rounded (no average) |
| `vc_blood_oxygen_pct_max` | percent, 0 to 100 | whole number, rounded (no average) |
| `vc_sleep_hours` | hours asleep | two decimals |
| `vc_sleep_deep_hours` | hours | two decimals |
| `vc_sleep_rem_hours` | hours | two decimals |
| `vc_sleep_source` | text | double-quoted YAML string, control characters escaped |
| `vc_weight_kg` | kg | one decimal |
| `vc_menstrual_flow` | category | the day's heaviest flow, see below |
| `vc_period_start` | flag | `true`, only when true |
| `vc_spotting` | flag | `true`, only when true |
| `vc_schema` | integer | always, the schema version |

Each minimum and maximum is written on its own. A missing minimum or maximum never hides the average.

### How each daily value is built

- Steps and exercise minutes are the day's sum. Resting and walking heart rate are the day's average. Heart rate, respiratory rate and blood glucose are the average plus the minimum and maximum. Blood oxygen is the minimum and maximum only.
- Weight is the sample on that start day with the latest `end`.
- Sleep counts only the `asleepUnspecified`, `asleepCore`, `asleepDeep` and `asleepREM` stages. Segments less than 4 hours apart form one night, and overlapping intervals are merged. Each source's longest night per wake day wins. Then one source is picked: the one chosen in the app's Settings if it has that night. If not, a night with an Apple Watch sample (the device name contains `Watch`). If not, the most asleep time, with ties going to the alphabetically first source.
- `vc_menstrual_flow` is the heaviest flow that day, ranked `none` < `unspecified` < `light` < `medium` < `heavy`. A value outside that list, such as `unknown(<n>)`, ranks below `none`.
- `vc_period_start` is `true` when any flow sample that day has `HKMenstrualCycleStart` equal to `1` or `true`.
- `vc_spotting` is `true` when the day has at least one spotting sample.

## 4. JSON month file

One file per type per month. Keys are sorted and slashes aren't escaped.

Top level: `generatedAt`, `period`, `samples`, `schemaVersion`, `type` and `unit`.

`period` has `start`, `end` and `timeZone`. It's the calendar month in the file name, taken in the export run's zone, with `end` exclusive. `period.start`, `period.end` and `generatedAt` are ISO 8601 without fractional seconds.

`period` is separate from which samples the file holds. Those follow each sample's own zone (section 2), so with travel data a sample near a month edge can sit in a file whose `period` doesn't strictly contain it.

Each sample has:

- `uuid`: HealthKit's.
- `start` and `end`: ISO 8601 with fractional seconds, in the sample's own zone.
- `value`: a number in the type's `unit`, or a category string (section 6).
- `source`: the app or device name that wrote the sample.
- `device`: always present, `null` when unknown.
- `metadata`: an object of string to string. HealthKit values are saved as text.

Samples are sorted by `start`, then `uuid`.

## 5. CSV month file

The same samples as the JSON, in the same order, with the same timestamps.

- The header is exactly `uuid,start,end,value,unit,source,device,metadata`.
- RFC 4180 quoting, LF line endings, UTF-8 without a byte order mark, and `.` as the decimal.
- `device` is empty when unknown. `metadata` is a JSON string with sorted keys.
- A `source` or `device` that starts with `=`, `+`, `-`, `@`, a tab or a carriage return gets a leading `'`, so a spreadsheet doesn't run it as a formula.
- Excel in some languages, pt-BR among them, may put everything in one column or garble accents, since the file has no byte order mark. Numbers, Google Sheets and pandas read it fine.

Compatibility is on its own terms (section 1). There's no version in the file, and the header is the contract. A breaking change goes to `csv-v2/` beside `csv/`.

## 6. Category values

When a type's unit is `category`, `value` is one of these strings.

Sleep: `inBed`, `asleepUnspecified`, `awake`, `asleepCore`, `asleepDeep`, `asleepREM`.

Menstrual flow: `unspecified`, `light`, `medium`, `heavy`, `none`.

Spotting: `notApplicable`.

Any value a later iOS adds comes out as `unknown(<n>)`, with HealthKit's raw integer. A later app version may give that value a name, and that isn't a breaking change (section 1). Renaming one of the named values above is.

## 7. Unit differences between the files

The JSON and CSV keep HealthKit's SI units. The note converts some of them.

- Exercise: seconds (`s`) in JSON and CSV, minutes in the note.
- Resting heart rate, walking heart rate average, heart rate and respiratory rate: `count/s` in JSON and CSV, per minute in the note (multiply by 60).
- Blood glucose: `g/L` in JSON and CSV, mg/dL in the note (multiply by 100).
- Blood oxygen: a 0 to 1 fraction in JSON and CSV, percent in the note (0.97 in the JSON is 97 in the note).

## 8. Export README and changelog

The `README.md` in the export folder belongs to the app and is rewritten on every export. It lists only the formats that are on, and ends with a link to this file.

Changelog:

- `1` (2026-11-07, app 0.3.13): first published version. It describes what the app has written since 0.3.11.
