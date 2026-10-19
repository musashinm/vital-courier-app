# Security policy

## Supported versions

Only the latest release on the App Store gets security fixes. Older builds, TestFlight builds included, don't.

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately through GitHub instead:

1. Go to the repository's **Security** tab.
2. Select **Report a vulnerability**, or open https://github.com/musashinm/vital-courier-app/security/advisories/new directly.
3. Describe the problem, the app and iOS versions, and the steps to reproduce it.

The report stays private between you and the repository's maintainers. Leave real health data out of it; made-up values are enough to show the problem.

## Scope

In scope: the iOS app in this repository, including how it stores Health data on the phone (the local SQLite database) and what it writes to the export folder.

Out of scope: the vitalcourier.app website, iCloud Drive or any other storage provider that syncs the export folder, and problems that need an already unlocked and compromised phone.
