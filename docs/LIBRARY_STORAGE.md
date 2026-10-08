# Library storage and safe cleanup

Settings → Storage shows the sizes of app-managed videos, generated system-wallpaper still images, and caches. Videos can be sorted by size or name and selected individually or in bulk. This implements issue #252.

## Ownership and accounting

- Library videos are copies in Wallnetic's Library directory, including imports, downloads, and generated videos that were imported there. Source files outside that directory are excluded and never deleted by cleanup.
- Generated still images are Wallnetic's system-wallpaper JPEGs. They remain protected because macOS and other Spaces may still use them. Separately retained optimized video copies are not currently produced; that feature remains #254.
- Caches include widget thumbnails and the SQLite search index (including WAL/SHM files). Cleanup removes only unused widget thumbnails. Current/library thumbnails and thumbnails referenced by widget data are protected; the live database is retained.
- Totals use logical file sizes, not allocated blocks. APFS clones, compression, snapshots and files held open by another process can change the actual disk space recovered. Bundled resources, user defaults, external originals, and in-progress temporary exports/downloads are not part of the managed-media total.

## Removal behavior

1. Refresh the scan before confirmation. Show the exact selected file count and estimated bytes for that snapshot.
2. Require explicit confirmation, including for the existing single-item Delete command. Cancel leaves files and assignments unchanged.
3. Restrict deletion to direct, regular files with expected names/extensions in known app-owned directories. Do not recurse into directories or follow symbolic links. Use descriptor-relative `unlinkat`, with component-by-component `O_NOFOLLOW` directory traversal.
4. Recheck the directory device/inode and file device/inode/size/modification time at deletion. Changed or missing files fail individually; files added after confirmation are not included.
5. Serialize removal with imports. Only successful removals update active playback, per-display and Space assignments, collection membership/playlist sources, time-of-day and weather paths, favorites, titles, tags, colors, search metadata and widget state. Failed removals retain their references.
6. Report individual failures and keep failed selections available for retry. Background scans support cancellation; filesystem work does not run on the main actor. Widget reference read failures disable cache deletion without disabling video cleanup.

Library rescans retain the UUIDs of surviving entries so directory-watcher notifications do not detach collection/display references during cleanup. This does not migrate historical collection records whose identities were already lost before the update.

In-flight metadata work rechecks surviving entries before committing. Widget synchronization uses separate current/favorites revisions so an older thumbnail task cannot restore removed content to widget state. Disk thumbnails that an already running generator finishes late can be collected by a later scan.

## Validation

Automated coverage includes ownership boundaries, original-file preservation, partial failure, changed and missing files, same-size replacement, symlink swaps, directory replacement, foreign snapshots, protected caches, canceled scans, confirmation/cancellation, repeated clicks, stable rescan identities, active/display reference pruning, and delayed widget updates. Widget reference reads reject symlinks, FIFOs, oversized records and malformed JSON.

On 2026-10-08, all 238 tests passed locally (19 storage regressions), and the universal Release build passed for arm64 and x86_64. The storage pane was rendered at 596 × 455 points using isolated fixture data to check the existing Settings window size.

Run the full suite using the repository CI recipe:

```sh
xcodebuild test \
  -project src/Wallnetic/Wallnetic.xcodeproj -scheme Wallnetic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/performance-profiles \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGN_ENTITLEMENTS= \
  ENABLE_APP_SANDBOX=NO DEBUG_INFORMATION_FORMAT=dwarf
```

Release-wide signed App Group, VoiceOver, physical Intel and multi-display lifecycle checks remain part of release preparation. This development does not change the app version or publish a release.
