# Downloaded wallpaper titles

Discover downloads and native browser downloads keep their available display
names when imported into Library, including ZIP/MLW conversion. The store
download handoff passes its known item name through the same import API.

Browser direct-link downloads use the current page title. Native WebKit downloads
capture that title when the download begins and keep it with the transfer, so
later navigation or another download does not replace the name. If the page has
no usable title, the server filename is the fallback.

Scan keeps the media URL and title together. A video/link's `title` or `aria-label`
takes precedence over the page's HTML title; the URL filename is the final
fallback. The same name appears in Scan results, download progress and Library.
Scanning another page does not mutate titles of previously captured results.
Titles are returned as data by a fixed DOM-reading script, never interpolated
into executable JavaScript. Scan accepts HTTP(S) media candidates, deduplicates
by URL and examines at most 200 returned candidates.

Temporary media continues to use generated filenames. On import, new browser
and store downloads with a usable title receive a readable Library filename,
for example `Ocean Sunset.mp4`. A separate filename conversion replaces reserved
characters (`/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`) with spaces, collapses
whitespace, removes leading/trailing dots and limits the stem to 180 bytes,
accounting for decomposed Unicode without splitting a composed character.
The actual imported media supplies the extension, including MP4 after conversion.
Raw titles are never interpreted as paths or commands.

Copying refuses an existing destination. If a filename collides, the new copy
gets a UUID suffix such as `Ocean Sunset (UUID).mp4`; existing files, directories
and symbolic links remain intact. Distinct downloads with the same title and
byte size are kept independently. An unusable title falls back to the generated
source name. Ordinary local imports without a title retain their filename and
duplicate-detection behavior.

`importVideo` records the full display name in the existing path-keyed custom-title
metadata before publishing the item and starting thumbnail/search processing.
Library rescans and relaunches restore it through the existing metadata store;
search indexes the same title. User renames take precedence over a later download
suggestion. The metadata key uses the final Library path.

Display titles remain plain text independently of the sanitized filename. Inputs above
4 KiB are ignored; whitespace is collapsed, control and bidirectional formatting
characters are removed, and the result is limited to 160 characters without
splitting a composed character. Empty results fall back to the filename. Unicode
letters and emoji remain supported. Two downloads with the same display title
remain independent library items; title equality is not file identity.

Existing UUID-only library entries are not guessed, renamed on disk or fetched
again. If their original names were not retained, users can rename those entries
with the existing Rename action, which edits display metadata. Existing Library
paths, assignments and pack receipts are not migrated. Curated pack files retain
their receipt-validated naming scheme. This change adds no permissions or network calls.

Regression coverage uses separate temporary files, an isolated preferences suite
per test and an in-memory search index. Metadata tests no longer clear the shared
preferences that a signed test host can share with the user's application.

Validation on 2026-10-13: 16 focused tests passed (9 metadata-store and 7
metadata-cache tests) on Apple silicon with Xcode 26.4, Apple Development signing
and the app sandbox enabled. The import regression copies an isolated synthetic
file, recreates the metadata store, rescans the library and rebuilds the search
index. It checks persistence and file preservation, not video decoding or a live
third-party download. End-to-end download UI checks remain part of local testing.

The page-title follow-up passed 23 focused tests with the sandbox enabled,
including seven browser metadata tests. Real WebKit HTML fixtures verify video
labels, page-title fallback, relative URLs, title changes and code-like title
text remaining inert. Fixtures use nonpersistent website storage and disable
page scripts/media requests with a content security policy.

On 2026-10-14, the filename follow-up passed 39 focused tests with the sandbox
enabled. Six filesystem tests cover readable names and trusted extensions,
same-title/same-size downloads, unsafe or unusable titles, long Unicode names,
and collisions with directories and live/dangling symlinks. Source bytes and
existing targets remain unchanged. The persistence test also rescans and searches
the newly named Library copy. These use isolated synthetic files, not a live
provider download or video-decoding test.
