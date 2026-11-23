# Localization (#351)

The interface text lives in string catalogs, one per bundle:

| Bundle | Catalog |
| --- | --- |
| App | `src/Wallnetic/Resources/Localizable.xcstrings` |
| Widget | `src/WallneticWidget/Resources/Localizable.xcstrings` |

English is the source language. The English text is the key.

## Writing interface text

- **SwiftUI literals are translatable as they are:** `Text("Play")`,
  `Button("Save")`, `Toggle("…")`, `.help("…")`, `Section("…")`.
- **Text that is built in code is not.** A `String` is shown as written, so
  wrap the literal:

  ```swift
  var title: String { String(localized: "Paused by you") }
  status = String(localized: "Playing on \(count) displays")
  ```

- **Write whole sentences.** Do not join fragments such as `"\(n)" + " files"`;
  a translation cannot reorder them. Put the value inside the sentence.
- **Do not compare interface text.** Give a choice an enum case and a
  `title`, as `LibraryView.Category` does.
- **Text that is not shown to the user** (log messages, keys, HTTP headers,
  internal diagnostics) stays a plain literal. If the check below reports it,
  add `// l10n:ignore` to its line.

## After changing text

`xcodebuild` does not write new strings into a catalog. After a build:

```bash
tools/l10n/sync_strings.sh <derived data folder>
```

This adds the new strings and drops untranslated ones that left the code.
Commit the catalogs with the code.

## Checks

CI runs both after the build:

| Check | What it catches |
| --- | --- |
| `python3 tools/l10n/check_strings.py --derived-data <folder>` | Prose in the app's sources that the compiler did not report as localizable: interface text that cannot be translated. |
| `tools/l10n/sync_strings.sh <folder> --check` | A string in the code that a catalog does not list. |

The first check reads the source lines the compiler lists in its
`.stringsdata` files, so it needs a finished build.

## Scope

- Features the app cannot open today keep their English text: the AI
  generator and its scheduler, collections, history, tagging, the in-app
  browser and the store. `check_strings.py` lists them in `IGNORED_FILES`.
- App Shortcuts phrases ("Next wallpaper in Wallnetic") need their own
  `AppShortcuts.xcstrings` catalog and are not translated yet.
- The Desktop Clock formats its text with the app's locale, so it follows
  the app's language once that language ships.
- Tests run with the scheme's language set to English, because they compare
  interface text.

## Status

The catalogs hold English only. No translation ships yet, so the app looks
and behaves as before.
