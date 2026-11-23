# Localization (#351)

Wallnetic's interface is in English, with draft translations into German,
French, Japanese and Simplified Chinese. macOS picks the language from the
system's language list and falls back to English, unless the user chooses
one in Settings.

## Choosing the language

Settings > General > **Language** offers System Default, English, Deutsch,
Français, 日本語 and 简体中文. A language is listed under its own name.

- The choice is the app's own language list, the value macOS also keeps for
  System Settings > Language & Region > Applications. Either place changes
  the same thing.
- macOS reads that list when an app starts, so a new choice shows after a
  restart. The row offers **Restart Now**, which starts a new copy with the
  same launch arguments and quits the old one.
- System Default removes the app's own list, and the Mac's list applies
  again.
- The widget is a separate program and follows the Mac's language list.

## Status

| Language | Code | State |
| --- | --- | --- |
| English | `en` | The source language. |
| German | `de` | Draft. Not reviewed by a native speaker. |
| French | `fr` | Draft. Not reviewed by a native speaker. |
| Japanese | `ja` | Draft. Not reviewed by a native speaker. |
| Simplified Chinese | `zh-Hans` | Draft. Not reviewed by a native speaker. |

- The drafts were written with AI assistance. Every translated string is
  marked `needs_review` in the catalogs, and Xcode shows it that way.
- **A draft ships like any other translation.** Before a release, each
  language is either reviewed by a native speaker or taken out of that build.
- The App Store listings are separate and are not updated yet.

## Where the text lives

| Text | File |
| --- | --- |
| App interface | `src/Wallnetic/Resources/Localizable.xcstrings` |
| Widget | `src/WallneticWidget/Resources/Localizable.xcstrings` |
| Photos permission text | `src/Wallnetic/Resources/InfoPlist.xcstrings` |
| App Shortcuts phrases | `src/Wallnetic/Resources/<language>.lproj/AppShortcuts.strings` |

- English is the source language, and the English text is the key.
- The phrases are in `.strings` files because a string catalog for App
  Shortcuts needs macOS 14, and Wallnetic supports macOS 13.

## Writing interface text

- **SwiftUI literals are translatable as they are:** `Text("Play")`,
  `Button("Save")`, `Toggle("…")`, `.help("…")`, `Section("…")`.
- **Text that is built in code is not.** A `String` is shown as written, so
  wrap the literal:

  ```swift
  var title: String { String(localized: "Paused by you") }
  ```

- **Write whole sentences.** Do not join fragments such as
  `"\(n)" + " files"`; a translation cannot reorder them. Put the value inside
  the sentence.
- **Counts:** write the plural sentence, `String(localized: "\(count) files")`,
  and give the catalog entry its singular form (see below). Do not add an "s"
  in code.
- **Do not show an enum's raw value.** A raw value is an identifier and is
  often stored. Give the type a `title`, as `LibrarySort` and
  `AppearanceMode` do.
- **Do not compare interface text.** Compare the enum case.
- **Text that is not shown to the user** (log messages, keys, HTTP headers,
  internal diagnostics) stays a plain literal. If the check below reports it,
  add `// l10n:ignore` to its line.

## After changing text

`xcodebuild` does not write new strings into a catalog. After a build:

```bash
tools/l10n/sync_strings.sh <derived data folder>
```

- It adds the new strings.
- It removes strings that left the code, with their translations.
- A changed English sentence is a new key: its old translations go, and the
  new key needs translating in every language.

Commit the catalogs with the code.

## Adding or changing translations

Edit the catalog in Xcode, or import a JSON file that maps each English key to
its translation:

```bash
python3 tools/l10n/catalog.py import src/Wallnetic/Resources/Localizable.xcstrings de german.json
```

- A value is a string, or `{"one": "…", "other": "…"}` where the language has a
  singular form. Japanese and Chinese need one form only.
- English singular forms are imported the same way, with the language `en`
  and `--state translated`.
- A translation must keep the placeholders of its key (`%@`, `%lld`, `%%`).
  When the word order differs, number them: `%1$@`, `%2$lld`.
- Imported text is marked `needs_review` unless `--state translated` is given.
- `python3 tools/l10n/catalog.py skip CATALOG keys.json` marks strings that are
  not to be translated: formats without words, and text of features the app
  cannot open.

The rules for translators and the terms each language uses for Wallnetic's
features are in [LOCALIZATION_GLOSSARY.md](LOCALIZATION_GLOSSARY.md).

## Checks

CI runs these after the build:

| Check | What it catches |
| --- | --- |
| `python3 tools/l10n/check_strings.py --derived-data <folder>` | Interface text in the app's sources that cannot be translated: prose the compiler did not report as localizable, two words joined by a symbol (`"Download & Import"`), a value joined to a word (`"\(n) files"` in a plain string), and an enum's raw value shown as text. |
| `tools/l10n/sync_strings.sh <folder> --check` | A string in the code that a catalog does not list. |
| `python3 tools/l10n/catalog.py check <catalogs>` | A string without a translation in one of the catalog's languages, or a translation whose placeholders differ from the English. |
| `python3 tools/l10n/check_shortcut_phrases.py` | A missing or outdated App Shortcuts phrase, or one without `${applicationName}`. |

The first two read the compiler's `.stringsdata` files, so they need a
finished build. The first check is a set of patterns, not a proof: it cannot
see a single lowercase word, or text that reaches the interface through data.
Looking at the screens in each language finds what it misses.

Its rules for what to leave out are narrow on purpose. A rule that skipped
every line containing the word `import` once hid four strings, among them an
error title and an alert's text.

## Looking at a language

Choose the language in Settings > General and restart. For a script, start
the app in a language without changing anything stored:

```bash
open -n Wallnetic.app --args -AppleLanguages "(de)"
```

Checked this way in German, French, Japanese and Simplified Chinese, in the
dark appearance on macOS 27:

- Home, Library and Discover at a window width of 1,000 points;
- every Settings page, with the long pages scrolled to the end;
- the four steps of the welcome tour;
- the Desktop Clock in German.

Not looked at in any translation yet: the menu bar menu and the context
menus, the sheets (preview, trim, optimize, wallpaper packs, import from a
link), error messages, the Dynamic Island, the widget, the Photos permission
prompt, the Shortcuts app, the light appearance, and macOS 13 to 26.

## Scope

- Features the app cannot open today keep their English text: the AI
  generator and its scheduler, collections, history, tagging, the in-app
  browser and the store. `check_strings.py` lists them in `IGNORED_FILES`,
  and their strings are marked as not to be translated.
- The Desktop Clock formats its text with the app's locale, so it follows the
  app's language. See [DESKTOP_CLOCK.md](DESKTOP_CLOCK.md).
- The names of the four default schedule ranges (Morning, Afternoon, Evening,
  Night) are translated when the schedule is first made. After that they are
  the user's own text and stay as they are.
- Tests run with the scheme's language set to English, because they compare
  interface text.
