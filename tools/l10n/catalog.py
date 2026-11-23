#!/usr/bin/env python3
"""Put translations into a string catalog, and check a catalog (#351).

  catalog.py import CATALOG LANGUAGE FILE.json [--state needs_review]
      FILE.json maps each English key to its translation: a string, or
      {"one": "…", "other": "…"} where the language needs both forms.

  catalog.py skip CATALOG FILE.json
      FILE.json lists keys that are not to be translated.

  catalog.py normalize CATALOG [CATALOG ...]
      Rewrite in the repository's format, changing nothing else.

  catalog.py prune CATALOG [CATALOG ...]
      Remove the strings that left the code (marked stale by a sync), then
      normalize.

  catalog.py check CATALOG [CATALOG ...]
      Every string that is to be translated must have a translation in every
      language the catalog ships, with the same placeholders as the English.

A catalog is always written in one format, with sorted keys.
"""
import json
import re
import sys

PLACEHOLDER = re.compile(r"%(?:\d+\$)?(lld|ld|d|@|\.\d+f|%)")


def placeholders(text):
    return sorted(PLACEHOLDER.findall(text)), text.count("\n")


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def save(path, catalog):
    # One stable format, keys sorted, whatever tool touched the file last.
    # sync_strings.sh normalizes with this after xcstringstool, so a change to
    # one string is a small diff.
    text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text + "\n")


def unit(value, state):
    return {"stringUnit": {"state": state, "value": value}}


def values(localization):
    """Every string a localization holds: one, or one per plural form."""
    if "stringUnit" in localization:
        return [localization["stringUnit"]["value"]]
    forms = localization.get("variations", {}).get("plural", {})
    return [form["stringUnit"]["value"] for form in forms.values()]


def import_translations(path, language, source, state):
    catalog = load(path)
    strings = catalog["strings"]
    translations = load(source)
    problems = []
    added = 0
    for key, value in translations.items():
        if key not in strings:
            problems.append("not in the catalog: %r" % key)
            continue
        forms = value if isinstance(value, dict) else {"other": value}
        bad = [form for form in forms.values() if placeholders(form) != placeholders(key) or not form.strip()]
        if bad:
            problems.append("placeholders differ: %r -> %r" % (key, bad[0]))
            continue
        entry = strings[key].setdefault("localizations", {})
        if isinstance(value, dict):
            entry[language] = {"variations": {"plural": {name: unit(form, state) for name, form in value.items()}}}
        else:
            entry[language] = unit(value, state)
        added += 1
    save(path, catalog)
    print("%s: %d translation(s) imported for %s" % (path, added, language))
    for problem in problems:
        print("  " + problem)
    return 1 if problems else 0


def skip(path, source):
    catalog = load(path)
    listed = load(source)
    keys = listed if isinstance(listed, list) else [key for group in listed.values() for key in group]
    count = 0
    for key in keys:
        if key in catalog["strings"]:
            catalog["strings"][key]["shouldTranslate"] = False
            count += 1
    save(path, catalog)
    print("%s: %d string(s) marked as not to be translated" % (path, count))
    return 0


def check(paths):
    status = 0
    for path in paths:
        strings = load(path)["strings"]
        languages = sorted({language for entry in strings.values()
                            for language in entry.get("localizations", {}) if language != "en"})
        missing = {language: [] for language in languages}
        broken = []
        for key, entry in strings.items():
            if entry.get("shouldTranslate") is False:
                continue
            localizations = entry.get("localizations", {})
            for language in languages:
                if language not in localizations:
                    missing[language].append(key)
                    continue
                for value in values(localizations[language]):
                    if placeholders(value) != placeholders(key):
                        broken.append((language, key, value))
        print("%s: %d string(s), languages: %s" % (path, len(strings), ", ".join(languages) or "none"))
        for language, keys in missing.items():
            if keys:
                status = 1
                print("  %s: %d untranslated, for example %r" % (language, len(keys), keys[0]))
        for language, key, value in broken[:20]:
            status = 1
            print("  %s: placeholders differ in %r -> %r" % (language, key, value))
    return status


def main():
    args = sys.argv[1:]
    if len(args) >= 4 and args[0] == "import":
        state = args[args.index("--state") + 1] if "--state" in args else "needs_review"
        sys.exit(import_translations(args[1], args[2], args[3], state))
    if len(args) == 3 and args[0] == "skip":
        sys.exit(skip(args[1], args[2]))
    if len(args) >= 2 and args[0] == "normalize":
        for path in args[1:]:
            save(path, load(path))
        sys.exit(0)
    if len(args) >= 2 and args[0] == "prune":
        for path in args[1:]:
            catalog = load(path)
            stale = [key for key, entry in catalog["strings"].items() if entry.get("extractionState") == "stale"]
            for key in stale:
                del catalog["strings"][key]
                print("%s: removed %r, which left the code" % (path, key))
            save(path, catalog)
        sys.exit(0)
    if len(args) >= 2 and args[0] == "check":
        sys.exit(check(args[1:]))
    sys.exit(__doc__)


if __name__ == "__main__":
    main()
