#!/bin/sh
# PostToolUse (Edit|Write): regenerates VitalCourier.xcodeproj after project.yml changes.
# Regenerates the checkout that owns the edited project.yml (its directory), which may be a worktree.
# The hook script itself always runs from the session's starting checkout (${CLAUDE_PROJECT_DIR}).
set -eu
file_path=$(jq -r '.tool_input.file_path // empty')
case "$file_path" in
  */project.yml) ;;
  *) exit 0 ;;
esac
repo_root=$(dirname "$file_path")
generate_script="$repo_root/scripts/generate-project.sh"
[ -x "$generate_script" ] || exit 0
if ! generate_output=$("$generate_script" 2>&1); then
  echo "project.yml changed, but scripts/generate-project.sh failed, so VitalCourier.xcodeproj is stale:" >&2
  echo "$generate_output" >&2
  exit 2
fi
