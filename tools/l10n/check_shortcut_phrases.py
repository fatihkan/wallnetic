#!/usr/bin/env python3
"""Check the translated App Shortcuts phrases (#351).

The phrases people say or type to run a shortcut are in
Services/AppShortcuts.swift. Their translations cannot live in a string
catalog while the app supports macOS 13, so each language has a
<language>.lproj/AppShortcuts.strings file. Every such file must translate
every phrase, and every translation must keep ${applicationName}.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "src/Wallnetic/Services/AppShortcuts.swift"
RESOURCES = ROOT / "src/Wallnetic/Resources"
PHRASE = re.compile(r'"([^"\n]*)\\\(\.applicationName\)([^"\n]*)"')
PAIR = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
NAME = "${applicationName}"


def main():
    phrases = {before + NAME + after for before, after in PHRASE.findall(SOURCE.read_text())}
    if not phrases:
        sys.exit("No phrases found in %s." % SOURCE)
    files = sorted(RESOURCES.glob("*.lproj/AppShortcuts.strings"))
    status = 0
    for path in files:
        pairs = dict(match.groups() for match in map(PAIR.match, path.read_text().split("\n")) if match)
        problems = ["missing: %r" % phrase for phrase in sorted(phrases - set(pairs))]
        problems += ["not in the code any more: %r" % key for key in sorted(set(pairs) - phrases)]
        problems += ["no %s in: %r" % (NAME, value) for value in pairs.values() if NAME not in value]
        print("%s: %d phrase(s)" % (path.relative_to(ROOT), len(pairs)))
        for problem in problems:
            status = 1
            print("  " + problem)
    print("%d phrase(s) in the code, %d language file(s)." % (len(phrases), len(files)))
    sys.exit(status)


if __name__ == "__main__":
    main()
