# Downloaded wallpaper titles

Discover downloads and native browser downloads keep their available display
names when imported into Library, including ZIP/MLW conversion. The store
download handoff passes its known item name through the same import API.

Temporary media continues to use generated filenames. `importVideo` accepts an
optional display name and records it in the existing path-keyed custom-title
metadata before publishing the item and starting thumbnail/search processing.
Library rescans and relaunches restore it through the existing metadata store;
search indexes the same title. User renames take precedence over a later download
suggestion. Local imports without a suggested title keep their filename fallback.

Suggested names are plain display text, never destination paths. Inputs above
4 KiB are ignored; whitespace is collapsed, control and bidirectional formatting
characters are removed, and the result is limited to 160 characters without
splitting a composed character. Empty results fall back to the filename. Unicode
letters and emoji remain supported. Two downloads with the same display title
remain independent library items; title equality is not file identity.

Existing UUID-only library entries are not guessed, renamed on disk or fetched
again. If their original names were not retained, users can rename those entries
with the existing Rename action. This change adds no permissions or network calls.

Regression coverage uses separate temporary files, an isolated preferences suite
per test and an in-memory search index. Metadata tests no longer clear the shared
preferences that a signed test host can share with the user's application.

Validation on 2026-10-13: 16 focused tests passed (9 metadata-store and 7
metadata-cache tests) on Apple silicon with Xcode 26.4, Apple Development signing
and the app sandbox enabled. The import regression copies an isolated synthetic
file, recreates the metadata store, rescans the library and rebuilds the search
index. It checks persistence and file preservation, not video decoding or a live
third-party download. End-to-end download UI checks remain part of local testing.
