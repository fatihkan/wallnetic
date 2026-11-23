#!/usr/bin/env python3
"""Find interface text that the app cannot translate (#351).

A string is translatable when the Swift compiler reports it as localizable:
a SwiftUI literal such as Text("…"), or String(localized: "…"). After a build,
the compiler leaves that list, with source lines, in *.stringsdata files.

This tool reads every string literal in the app's sources that looks like
prose and reports the ones the compiler did not list. Text that is not shown
to the user is skipped by the patterns below, by IGNORED_FILES, or by an
`l10n:ignore` comment on its line or the line above.

usage: check_strings.py --derived-data PATH [--list] [FILE ...]
exit status 1 when unlocalized interface text is found.
"""
import argparse
import collections
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "src/Wallnetic"

# Features the app cannot open today. Their text stays in English until they
# return (#351): the AI generator and its scheduler, collections, history,
# tagging, the in-app browser and the store.
IGNORED_FILES = [
    r"^Tests/",
    r"^Models/AI\w*\.swift$", r"^Models/GenerationHistory\.swift$", r"^Models/Collection\w*\.swift$",
    r"^ViewModels/AIGenerateViewModel\.swift$",
    r"^Views/Main/(AIGenerateView|HistoryView|BrowserWebView|VideoPreviewView|NowPlayingOverlayView)\.swift$",
    r"^Views/Collections/", r"^Views/Settings/(SchedulerSettingsView|SmartTaggingSettingsView)\.swift$",
    r"^Services/(AIService|SchedulerService|SupabaseClient|UsageTracker|Ollama\w*|NotificationManager"
    r"|WallpaperStoreManager|CollectionManager|NowPlayingManager|AudioVisualizerManager)\.swift$",
]

# Lines whose strings are not interface text: logs, stored settings and
# declarations. The words must be code, so `import` counts only as a
# statement: a rule that matched it anywhere skipped every line with a string
# such as "Drag & drop import failed".
SKIPPED_LINE = re.compile(
    r"\b(Log\.\w+\.|logger\.|print\(|fatalError\(|assertionFailure\(|precondition\(|preconditionFailure\("
    r"|NSLog\(|os_log|Logger\(|UserDefaults|@AppStorage|#available|#Preview|sqlite3_|PRAGMA )"
    r"|^\s*import\s|^\s*case\s+\"|^\s*case .*= \"|^\s*@available"
)
# One string that is a key, a symbol name or a path, right after its label.
# Only that string is left out; other strings on the line are still checked.
SKIPPED_ARGUMENT = re.compile(
    r"(?:forKey:|Notification\.Name\(|systemImage:|systemName:|named:|CIFilter\(name:|DispatchQueue\(label:"
    r"|withExtension:|forResource:|URL\(string:|appendingPathComponent\(|makeFunction\(name:|keyPath:)"
    r'\s*"(?:[^"\\\n]|\\.)*"'
)
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


# A value followed by a word, as in "\(count) files" or "%d files": text that
# is put together in code.
VALUE_THEN_WORD = re.compile(r"(?:\\\([^()]*\)|%[\d.$]*(?:lld|ld|d|@|f)) ?[A-Za-z]{3,}")


# An enum's raw value used as interface text, as in Text(mode.rawValue). A raw
# value is an identifier, often a stored one: the type needs a localized title.
RAW_VALUE_TEXT = re.compile(
    r"\b(?:Text|Label|Button|Toggle|Picker|Section|Menu)\(\s*[\w.$]+\.rawValue\b"
    r"|\.(?:help|accessibilityLabel|accessibilityValue|accessibilityHint|navigationTitle)\(\s*[\w.$]+\.rawValue\b"
    r"|\brawValue\.capitalized\b"
)
RAW_VALUE_IN_TEXT = re.compile(r"\\\([\w.$]+\.rawValue\)")
RAW_VALUE_NOTE = "a raw value shown as text; give the type a localized title"


def is_prose(text):
    """A capitalized word, or words with spaces: something a person reads."""
    if len(text) < 3 or not re.search(r"[A-Za-z]{3,}", text):
        return False
    if VALUE_THEN_WORD.search(text):
        return True
    if " " not in text.strip():
        return bool(re.fullmatch(r"[A-Z][a-z]+(?:…|\.\.\.)?", text))
    # SQL, format-only strings and paths are not prose.
    if re.match(r"\s*(SELECT|INSERT|DELETE|UPDATE|CREATE|BEGIN|COMMIT|ROLLBACK|DROP)\b", text):
        return False
    # A label in capitals beside other text, as in "01 · IMPORT".
    if " " in text.strip() and re.search(r"(?<![A-Za-z])[A-Z]{4,}(?![A-Za-z])", text):
        return True
    if re.search(r"[A-Za-z]{2,} [A-Za-z(\\]", text):
        return True
    # Two words with something else between them, as in "Download & Import".
    # Names inside \( … ) are code, not words.
    plain = re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "", text)
    plain = re.sub(r"\\\(.*$", "", plain)
    return len(re.findall(r"[A-Za-z]{3,}", plain)) >= 2


def localized_lines(derived_data):
    """{source path: lines where the compiler found a localizable string}."""
    found = collections.defaultdict(set)
    for path in pathlib.Path(derived_data).rglob("Wallnetic.build/Objects-normal/*/*.stringsdata"):
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        source = data.get("source")
        if not source:
            continue
        for entries in data.get("tables", {}).values():
            for entry in entries:
                found[pathlib.Path(source).name].add(entry.get("location", {}).get("startingLine"))
    return found


def candidates(source, localized):
    relative = str(source.relative_to(APP))
    lines = source.read_text().split("\n")
    in_block_string = False
    for number, line in enumerate(lines, 1):
        if line.count('"""') % 2 == 1:
            in_block_string = not in_block_string
            continue
        if in_block_string or line.lstrip().startswith("//"):
            continue
        code = line.split(" // ")[0]
        if "l10n:ignore" in line or (number > 1 and "l10n:ignore" in lines[number - 2]):
            continue
        if RAW_VALUE_TEXT.search(code) or (number in localized and RAW_VALUE_IN_TEXT.search(code)):
            yield relative, number, RAW_VALUE_NOTE
            continue
        if SKIPPED_LINE.search(code) or number in localized:
            continue
        code = SKIPPED_ARGUMENT.sub("", code)
        for match in LITERAL.finditer(code):
            if is_prose(match.group(1)):
                yield relative, number, match.group(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--derived-data", required=True)
    parser.add_argument("--list", action="store_true", help="print every finding")
    parser.add_argument("files", nargs="*", help="limit to these files, relative to src/Wallnetic")
    args = parser.parse_args()

    localized = localized_lines(args.derived_data)
    if not localized:
        sys.exit("No .stringsdata files under %s. Build the app first." % args.derived_data)
    ignored = [re.compile(pattern) for pattern in IGNORED_FILES]
    findings = collections.defaultdict(list)
    for source in sorted(APP.rglob("*.swift")):
        relative = str(source.relative_to(APP))
        if any(pattern.search(relative) for pattern in ignored):
            continue
        if args.files and relative not in args.files:
            continue
        for _, number, text in candidates(source, localized.get(source.name, set())):
            findings[relative].append((number, text))

    total = sum(len(items) for items in findings.values())
    for relative, items in sorted(findings.items(), key=lambda item: (-len(item[1]), item[0])):
        print("%4d  %s" % (len(items), relative))
        if args.list or args.files:
            for number, text in items:
                print("      %s:%d: %s" % (relative, number, text[:110]))
    if total:
        print("\n%d string(s) are shown to the user but cannot be translated." % total)
        print("Wrap each in String(localized:), or mark it `// l10n:ignore` if it is not interface text.")
        sys.exit(1)
    print("Every interface string is localizable.")


if __name__ == "__main__":
    main()
