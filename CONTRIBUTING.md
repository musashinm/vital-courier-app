# Contributing to Vital Courier

Bug reports, feature requests and pull requests are welcome. By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Issues

Bug reports and feature requests go through the issue forms. Issues are public, so don't paste health data into one; describe the values or use made-up ones.

Security problems don't go in issues. See [SECURITY.md](SECURITY.md).

For anything bigger than a small fix, open a feature request first, so we can agree on the approach before you write the code.

## Building and testing

The requirements and commands are in the README's [Building and testing](README.md#building-and-testing) section. `VitalCourier.xcodeproj` is generated from `project.yml` and isn't committed. `project.yml` sets the author's development team, so use your own team and bundle ID for a real iPhone, and leave those changes out of your pull request.

## Project rules

- The app ships in English and Brazilian Portuguese. Every new string in the String Catalogs (`App/Resources/*.xcstrings`) needs a pt-BR translation, and `scripts/check-translations.sh` fails without one. If Xcode reformats a catalog you didn't mean to change, restore it instead of committing the noise.
- Migrations on `main` are frozen. Change the schema by adding a new migration with a new ID, never by editing an old one. `scripts/check-migrations.sh` catches edits, removals and reordering.
- Swift code is formatted with swift-format, which ships with Xcode (2 spaces, 120 columns). Fix formatting with `xcrun swift-format format --in-place --parallel --recursive App AppTests VitalCourierCore/Package.swift VitalCourierCore/Sources VitalCourierCore/Tests`. `scripts/check-format.sh`, the first step of `scripts/verify.sh`, fails on any finding.
- The project uses Swift 6 with complete strict concurrency. Don't add `@unchecked Sendable`, `nonisolated(unsafe)`, `try?` or an empty `catch` in Sources.

## Pull requests

- One change per pull request.
- Fill in `.github/pull_request_template.md` and tick only the boxes that are true.
- Add tests for the change. A new test should fail before your fix and pass after it.
- `swift test --package-path VitalCourierCore` must pass.

## License

Vital Courier is under the [MIT License](LICENSE). Your contributions are released under it too.
