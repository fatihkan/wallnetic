#!/bin/bash
# Bring the string catalogs up to date with the code (#351).
#
# xcodebuild does not write new strings back into a .xcstrings file. After a
# build, this merges what the compiler found into each target's catalog.
# Translations already in a catalog are kept. A string that left the code is
# removed with its translations, because nothing can show it any more.
#
# usage: tools/l10n/sync_strings.sh DERIVED_DATA [--check]
#   --check  change nothing; fail when a catalog is missing a string.
set -euo pipefail

derived_data="${1:?usage: sync_strings.sh DERIVED_DATA [--check]}"
check="${2:-}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
status=0

sync() {
  local target="$1" catalog="$2"
  local files=()
  while IFS= read -r file; do files+=("$file"); done < <(
    find "$derived_data" -path "*/${target}.build/Objects-normal/*" -name '*.stringsdata' 2>/dev/null)
  if [ "${#files[@]}" -eq 0 ]; then
    echo "No .stringsdata for ${target} under ${derived_data}. Build first." >&2
    exit 2
  fi
  if [ "$check" = "--check" ]; then
    local copy
    # The file name is the table name, so the copy keeps it.
    copy="$(mktemp -d)/$(basename "$catalog")"
    cp "$catalog" "$copy"
    xcrun xcstringstool sync "$copy" --stringsdata "${files[@]}"
    if ! python3 - "$catalog" "$copy" <<'PY'
import json, sys
have = set(json.load(open(sys.argv[1]))["strings"])
want = set(k for k, v in json.load(open(sys.argv[2]))["strings"].items() if v.get("extractionState") != "stale")
missing = sorted(want - have)
for key in missing[:20]:
    print("  missing: %r" % key)
sys.exit(1 if missing else 0)
PY
    then
      echo "${catalog#$root/} is missing strings. Run tools/l10n/sync_strings.sh after a build." >&2
      status=1
    fi
  else
    xcrun xcstringstool sync "$catalog" --stringsdata "${files[@]}"
    # Drop what left the code and keep one file format, so a new string is
    # a small diff.
    python3 "$root/tools/l10n/catalog.py" prune "$catalog"
    echo "Synced ${catalog#$root/}"
  fi
}

sync Wallnetic "$root/src/Wallnetic/Resources/Localizable.xcstrings"
sync WallneticWidget "$root/src/WallneticWidget/Resources/Localizable.xcstrings"
exit $status
