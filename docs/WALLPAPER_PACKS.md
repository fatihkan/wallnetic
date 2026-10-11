# Optional wallpaper packs

Issue: [#258](https://github.com/fatihkan/wallnetic/issues/258).

Discover → Browse Packs offers the original **Soft Motion** pack (Lagoon and
Ember). The two silent six-second H.264 loops total **690,598 bytes**, at
1280 × 720 and 30 fps. Previews, individual and total sizes, compatibility,
creator, license and attribution appear before download. MIT license text is
available in the window. No account, subscription or catalog is required for
local imports or playback.

## Download and offline behavior

- Opening Discover/Packs makes no network request. The application includes a
  small catalog with JPEG previews, not the optional videos.
- **Refresh Catalog** explicitly requests the published catalog. A validated
  newer revision replaces the saved catalog. Lower revisions or changed content
  under the same revision are rejected. Invalid/unavailable updates leave the
  previous catalog intact. A valid saved catalog takes priority over an older
  bundled catalog. A damaged cache falls back to the bundled copy.
- Downloads start only from **Download Pack / Download / Retry** and show byte
  progress. One operation runs at a time across windows. Closing the sheet keeps
  a download running; **Cancel** stops it. A completed file stays in the library
  if a later item fails or cancellation arrives during its final installation.
  Retry verifies completed copies and downloads only missing items. Partial
  copies are never installed. No wallpaper is automatically applied.
- Installed copies work offline and are not silently updated. A catalog update
  never overwrites a library file. If a pack changes, explicitly downloading it
  adds the changed item as a new copy; Remove Copies covers all owned versions.
- Refresh is manual: there is no background polling, scheduled transfer,
  analytics, credential, tracking identifier, custom server or sign-in.

## Bounds and trust

Catalog schema 1 accepts at most 512 KiB, 20 packs and four items per pack.
Identifiers, display text, uniqueness and numeric metadata are bounded. Each
JPEG is at most 64 KiB and 640 × 360 pixels; image type/dimensions are checked
before SwiftUI decodes it. This first schema permits only MIT content. A new
license requires an app/schema change with the appropriate bundled license text.

Media are limited to 8 MiB each (32 MiB per pack), 3840 × 2160, 30 fps and
30 seconds, with one silent H.264 track. URLs must match the exact HTTPS raw
GitHub origin, `fatihkan/wallnetic`, a 40-digit immutable commit and
`catalog/media/<safe-name>.mp4`. Redirects, alternate hosts/ports, URL credentials,
query strings, encoded paths, branch references and other formats are rejected.
Requests use a fresh ephemeral session, no cookies/cache, and 30-second request /
180-second resource timeouts. Both declared and streamed lengths are bounded;
HTTP errors are not imported. Cancellation invalidates that request's session.

Every media file must match its declared length and SHA-256 before inspection.
The MP4 structure must contain a self-contained data reference, not a reference
movie. AVFoundation then verifies playability, no protection/audio/extra tracks,
H.264 descriptions, encoded and display dimensions, duration and frame rate.
Verification uses a private temporary directory removed on completion/failure.
No archives, scripts, HTML renderers or downloaded executable code are supported.

SHA-256 validates media integrity against the catalog; it is **not an independent
publisher signature**. The catalog publisher, GitHub account/repository access,
HTTPS and the platform media decoder remain trust boundaries. These checks do
not constitute a promise that a media decoder has no vulnerabilities.

## Installation, ownership and removal

Remote names never become destination paths. Each copy gets a locally generated
`pack-<UUID>.mp4` filename. The import/removal permit serializes library writes.
Installation opens the anchored library directory without following symlinks,
uses descriptor-relative `openat` with `O_EXCL`/`O_NOFOLLOW`, bounds the write and
never overwrites an existing file.

Small local receipts record pack/item IDs, SHA-256, generated filename, file
identity (device, inode, size, modification time) and directory identity. Removal
requires matching identity **and** bytes; the existing Library Storage removal
flow rechecks identity before unlink and cleans the successfully removed files'
playlists, schedules, display assignments and other references. Edited, replaced,
renamed or unidentifiable files are kept as ordinary user library content; their
pack receipt is relinquished. A failed unlink keeps its receipt for retry.
Missing files are forgotten. Packs withdrawn from the catalog retain a separate
removal entry while their receipts exist.

Receipts survive relaunch and contain no catalog-controlled filesystem path.
Malformed/oversized receipts disable pack installation/removal rather than infer
ownership. Library Storage remains available. An abrupt process/system crash
between a successful file write and receipt persistence can leave an ordinary
untracked library copy; it is deliberately not adopted or deleted automatically.
Defaults persistence is not an atomic transaction with filesystem installation.
This flow does not defend against a hostile process with the same user's ability
to modify application data during individual filesystem operations.

## Rights and publishing ownership

[Per-item provenance, hashes and attribution](../catalog/media/README.md) cover
both videos and previews. All creative media are original mathematical gradients
from `tools/generate-wallpaper-pack.swift`, with no third-party footage or audio.
The repository [MIT license](../LICENSE) applies to the generator and outputs.
Copies of its copyright and permission notice must accompany redistribution.

**Publisher and operational owner:** repository owner `fatihkan` (Fatih Kan).
Catalog/content changes require repository review, provenance, hashes and passing
catalog/media tests. Community uploads and automatic catalog contributions are
not supported. Do not add third-party content without documenting redistribution
permission and all attribution obligations first.

The refresh URL reads `main/catalog/wallpaper-packs-v1.json`. During development
on `dev`, a missing/unpublished main catalog leaves the bundled catalog usable.
The production catalog is published when this reviewed development is promoted
to main as part of release preparation. This feature does not change the current
application version or trigger an App Store/DMG release.

Media URLs pin the asset commit. **Preserve that commit in dev/main history**:
merge this feature using a merge commit, not squash/rebase. Future content
publishing must likewise retain the immutable asset commit before generating the
manifest; never repoint an existing manifest revision. Increment `revision`, copy
exactly the same manifest to `src/Wallnetic/Resources/wallpaper-packs-v1.json`, and
run the pack tests. Published revisions must increase monotonically.

## Hosting budget and removal procedure

The initial small pack uses the existing public GitHub repository/raw endpoint;
no paid service, cloud account or recurring spend is introduced. Each video is
under 1 MB and the catalog is approximately 24 KB. This is a deliberately small
initial catalog, not an unlimited CDN or availability guarantee. The owner should
review GitHub availability/throttling and repository growth before adding packs.
If demand requires dedicated object storage/CDN, stop expanding the catalog and
approve that provider, budget and app origin/schema change separately. Do not
silently accept alternate media origins. GitHub recommends limiting repository
binary growth; see [repository limits](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits).

For a content-rights complaint, contact the owner through the repository issue
tracker (use the contact links in [PRIVACY.md](../PRIVACY.md) instead of posting
private details publicly). The owner should:

1. Verify the affected IDs, provenance and complaint; stop further publication.
2. Remove affected items/packs from a higher-revision main catalog and the next
   bundled catalog. An empty pack list is a supported emergency catalog.
3. Document the withdrawal without republishing disputed media. Users who refresh
   stop seeing the offer; existing personal library copies remain under user
   control. There is no silent remote deletion.
4. If the binary itself must be made unavailable, work with GitHub to remove it
   from hosting/history as appropriate. A new catalog alone cannot revoke old
   immutable URLs or offline cached catalogs. Do not claim immediate global
   revocation; communicate this limitation and any required application update.

## Validation

The automated suite exercises catalog/URL limits, bundled rights, actual original
media, hash/metadata/reference-movie rejection, bounded/chunked HTTP responses,
redirect refusal, stalled-transfer cancellation, offline/cache revisions,
partial retry and relaunch, corrupt receipts, and changed/replaced/symlink file
preservation. Tests use isolated temporary libraries and preferences.

Development validation on macOS 26.6.2 / Apple Silicon: all **349 local tests**
passed, including **22 pack tests**. Both app and widget built for arm64 and
x86_64. A separate native harness downloaded both pinned GitHub assets through
the actual transfer service and passed SHA-256/media checks. Light/dark pack
screens were rendered and inspected at 740 × 700. Test fixtures are bundled
inside the test target to avoid checkout/removable-volume access prompts.

Before release, additionally verify the signed sandbox build's download/cancel/
remove flow and VoiceOver on supported macOS versions. Local ad-hoc tests and
unsigned preview harnesses are not substitutes for those release checks.
