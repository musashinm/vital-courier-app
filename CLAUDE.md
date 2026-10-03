# Vital Courier

## Pull requests

- Every PR description follows `.github/pull_request_template.md`: an opening paragraph, then `## What's in it`, `## Related issue`, `## Type of change`, `## What's tested` and `## Checklist`, in that order. Replace the HTML comments with real content, tick only the boxes that are true, and don't add sections the template doesn't have.
- When a PR changes, update its description so it still follows the template.

## Database migrations

- Every GRDB migration registered under `VitalCourierCore/Sources/VitalCourierCore` (today only `LocalStore.migrator`) that is on `main` is frozen. Change the schema only by appending a new `registerMigration` with a new ID.
- At the final build, alongside the final Codex review (dispatched in the same turn, not as a Codex task), run `scripts/check-migrations.sh`. If it fails, fix that before merging.
- If it lists new migrations, also dispatch a fresh Sonnet subagent in that same turn, with this checklist and the script's output:
  1. A test in `VitalCourierCoreTests` builds a database at the previous migration (`migrator.migrate(dbQueue, upTo: "<previous id>")`), inserts representative rows, runs the full migrator, and asserts the rows survive in the new shape.
  2. The new migration doesn't depend on helpers or constants that later code may change. Inline its SQL.
  3. `LocalStore.open` still calls `protectFiles()` after `migrate`, and nothing deletes or recreates the database when migration fails (the blocker screen handles that).
  4. Run `swift test --package-path VitalCourierCore` and report the real output.
