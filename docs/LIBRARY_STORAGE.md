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
3. Restrict deletion to direct, regular files with expected names/extensions in known app-owned directories. Do not recurse into directories or follow symbolic links. Open the physical owned-directory anchor with `O_NOFOLLOW_ANY`, then use descriptor-relative file operations and `unlinkat`. The kernel rejects symbolic links anywhere in that directory lookup without requiring separate opens of sandbox-inaccessible ancestors.
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

### Signed sandbox directory access — 2026-10-13

A local Apple Development-signed Release build exposed a shared failure: Storage
showed no files and pack downloads stopped with `NSPOSIXErrorDomain` / `EPERM`
after successful transfer and media validation. The former directory walker
opened each ancestor using `O_EVTONLY`; App Sandbox denied opening `/Users` even
though the final application-container directory was accessible.

The directory opener now targets only the physical owned directory with
`O_DIRECTORY | O_NOFOLLOW_ANY`. The existing logical-to-physical anchor check,
file/directory identity checks, exclusive pack creation and descriptor-relative
deletion remain in place. No entitlement or sandbox setting changes.
[Apple's XNU definition](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/bsd/sys/fcntl.h#L169)
specifies the no-symlink path flag; the
[kernel lookup implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_vnops.c)
rejects a symlink encountered anywhere in that lookup.

A signed probe using the app's actual entitlements and a unique temporary test
directory reproduced both failures before the fix. Afterwards, Storage scanning
and both real Soft Motion downloads passed, including media/hash validation,
installation, receipt verification and removal; an unrelated fixture was kept.
The probe never installed pack content into the user's real library.

All **43 focused storage and pack tests passed with Apple Development signing and
App Sandbox enabled** on Apple M4 / macOS 26.6.2. The rebuilt signed Release app
also displayed the real library sizes in Storage and reported Soft Motion as
installed through the Packs UI. Other release-wide device checks remain pending.

`LibraryStorageTests.testApplicationSupportStorageCanScanInstallVerifyAndRemove`
provides a repeatable application-support-path regression. Run it with the app's
development signing and entitlements enabled to exercise App Sandbox; the default
CI recipe above deliberately disables sandboxing and cannot establish this result:

```sh
xcodebuild test \
  -project src/Wallnetic/Wallnetic.xcodeproj -scheme Wallnetic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/storage-signed-tests \
  -only-testing:WallneticTests/LibraryStorageTests/testApplicationSupportStorageCanScanInstallVerifyAndRemove \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_IDENTITY='Apple Development'
```

Use an existing development profile for this device and both app targets. The test
creates and removes only its uniquely named `WallneticStorageTests-*` directory;
it does not remove user library files. A second regression verifies that replacing
an ancestor with a symlink cannot redirect scanning, installation or deletion.
