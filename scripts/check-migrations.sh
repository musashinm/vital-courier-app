#!/bin/sh
# Compares the GRDB migrations registered on the base ref with the working tree.
# Fails when a migration from the base was edited, removed or reordered.
# Prints the IDs of new migrations, so the caller knows whether a deeper check is needed.
set -eu
cd "$(dirname "$0")/.."
base_ref=${1:-origin/main}
store_dir=VitalCourierCore/Sources/VitalCourierCore
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# Prints "== <id>" and then the closure body for each registerMigration call on stdin.
extract_migrations() {
  awk '
    /registerMigration\("/ {
      match($0, /registerMigration\("[^"]*"/)
      print "== " substr($0, RSTART + 19, RLENGTH - 20)
      inside = 1; depth = 0
    }
    inside {
      print
      opened = gsub(/\{/, "{"); closed = gsub(/\}/, "}")
      depth += opened - closed
      if (depth <= 0 && opened + closed > 0) inside = 0
    }
  '
}

for swift_file in $(git ls-tree -r --name-only "$base_ref" "$store_dir/" | grep '\.swift$' | sort); do
  git show "$base_ref:$swift_file" | extract_migrations
done > "$work_dir/base"
for swift_file in $(find "$store_dir" -name '*.swift' | sort); do
  extract_migrations < "$swift_file"
done > "$work_dir/head"

grep '^== ' "$work_dir/base" | cut -c4- > "$work_dir/base_ids" || true
grep '^== ' "$work_dir/head" | cut -c4- > "$work_dir/head_ids" || true
base_count=$(wc -l < "$work_dir/base_ids" | tr -d ' ')

if ! head -n "$base_count" "$work_dir/head_ids" | cmp -s - "$work_dir/base_ids"; then
  echo "FAIL: migrations from $base_ref were removed or reordered." >&2
  diff "$work_dir/base_ids" "$work_dir/head_ids" >&2 || true
  exit 1
fi

failed=0
while read -r migration_id; do
  awk -v id="$migration_id" '$0 == "== " id {on=1; next} /^== / {on=0} on' "$work_dir/base" > "$work_dir/base_body"
  awk -v id="$migration_id" '$0 == "== " id {on=1; next} /^== / {on=0} on' "$work_dir/head" > "$work_dir/head_body"
  if ! cmp -s "$work_dir/base_body" "$work_dir/head_body"; then
    echo "FAIL: migration \"$migration_id\" from $base_ref was edited. Add a new migration instead." >&2
    diff -u "$work_dir/base_body" "$work_dir/head_body" >&2 || true
    failed=1
  fi
done < "$work_dir/base_ids"
[ "$failed" -eq 0 ] || exit 1

new_ids=$(tail -n +"$((base_count + 1))" "$work_dir/head_ids")
if [ -z "$new_ids" ]; then
  echo "OK: $base_count migration(s) from $base_ref unchanged; no new migrations."
else
  echo "OK: $base_count migration(s) from $base_ref unchanged. New migrations:"
  echo "$new_ids"
fi
