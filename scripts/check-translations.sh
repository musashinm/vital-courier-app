#!/bin/sh
# Fails when a String Catalog in App/Resources has an entry without a translated pt-BR form.
# With a DerivedData path, also fails when the app's code uses a Localizable string the catalog doesn't list:
# the build's .stringsdata files are merged into a scratch copy, and any key that appears there is missing here.
set -eu
cd "$(dirname "$0")/.."
derived_data=${1:-}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

if [ -n "$derived_data" ]; then
  find "$derived_data" -path '*VitalCourier.build*' -name '*.stringsdata' -exec printf -- '--stringsdata\0%s\0' {} + > "$work_dir/stringsdata-args"
  if [ ! -s "$work_dir/stringsdata-args" ]; then
    echo "No .stringsdata files under $derived_data: build the app first." >&2
    exit 1
  fi
  cp App/Resources/Localizable.xcstrings "$work_dir/Localizable.xcstrings"
  # NUL-separated so a DerivedData path with spaces survives.
  xargs -0 xcrun xcstringstool sync "$work_dir/Localizable.xcstrings" --skip-marking-strings-stale < "$work_dir/stringsdata-args"
fi

python3 -I - "$work_dir" "$derived_data" <<'PY'
import json
import pathlib
import sys

work_dir = pathlib.Path(sys.argv[1])
checks_code_usage = bool(sys.argv[2])
target_language = "pt-BR"
problems = []


def leaves(node, path=""):
    """Yields (path, stringUnit) for every string under one localization, through variations and substitutions."""
    if "stringUnit" in node:
        yield path, node["stringUnit"]
    for kind, cases in node.get("variations", {}).items():
        for case, child in cases.items():
            yield from leaves(child, f"{path}/{kind}.{case}")
    for name, substitution in node.get("substitutions", {}).items():
        yield from leaves(substitution, f"{path}/substitution:{name}")


for catalog_path in sorted(pathlib.Path("App/Resources").glob("*.xcstrings")):
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    source_language = catalog["sourceLanguage"]
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        target = localizations.get(target_language)
        if target is None:
            problems.append(f"{catalog_path.name}: {key!r} has no {target_language} value")
            continue
        target_leaves = list(leaves(target))
        for path, unit in target_leaves:
            if unit.get("state") != "translated":
                problems.append(f"{catalog_path.name}: {key!r} {target_language}{path} is {unit.get('state')!r}, not 'translated'")
        target_paths = {path for path, _ in target_leaves}
        for path, _ in leaves(localizations.get(source_language, {})):
            if path not in target_paths:
                problems.append(f"{catalog_path.name}: {key!r} has a {source_language} form at '{path or '/'}' that {target_language} lacks")

if checks_code_usage:
    listed_keys = set(json.loads(pathlib.Path("App/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"])
    used_keys = set(json.loads((work_dir / "Localizable.xcstrings").read_text(encoding="utf-8"))["strings"])
    for key in sorted(used_keys - listed_keys):
        problems.append(f"Localizable.xcstrings: the code uses {key!r}, which the catalog doesn't list")

for problem in problems:
    print(problem, file=sys.stderr)
if problems:
    sys.exit(1)
print("Translations complete.")
PY
