# PR #238: independent review and playback hardening

Reviewed merge commit `4fd2016fedd04fbb819e77d2e37da82be3b39227` against its parent, including all 13 changed source/configuration/test files and the three original commit descriptions. A separate review agent independently checked the original diff and the subsequent corrections.

## Security assessment

No injection, backdoor, new network destination, data transmission, shell/process execution, downloaded executable, added dependency, entitlement expansion, startup persistence or build script was identified in this change. The Metal shader is a fixed source literal. The Xcode project changes register Swift files; the process activity options affect power management, not access privileges.

This conclusion is limited to the reviewed change and targeted runtime checks. It is not a guarantee that the application or every media input is free of vulnerabilities. The recommendation is to retain the useful rendering corrections with the hardening below; the evidence does not support reverting the entire PR on grounds of malicious code.

## Corrections

- **Display-link data race:** the original Core Video callback accessed `drawScheduled` and playback intent concurrently with the main thread. A Thread Sanitizer run of the actual renderer reported two conflicting accesses to `drawScheduled`. The callback now owns a separate lock-protected scheduler. Renderer state is read on the main queue, and queued frames are invalidated before stopping a session. A retained callback block replaces the unretained renderer pointer.
- **Failed replacement freezing the current wallpaper:** the old loop callback used the pending load's generation to determine ownership. Starting a replacement disabled the existing player's loop even if the replacement failed. Loop callbacks now identify the active player; seek completions return to main, check success and identity, and respect pause/stop.
- **Stale loads:** stop cancels and invalidates outstanding loads. Metal checks the generation after all metadata awaits, before changing the current crop. Both loaders avoid holding the renderer across asset-loading suspension points and accept file URLs only.
- **Unnecessary sleep prevention:** removed `.idleSystemSleepDisabled` and global `NSAppSleepDisabled`. Playback keeps its scoped activity to avoid App Nap while allowing idle system sleep; pause/cleanup ends it.
- **Misleading transition controls:** PR #238 removed the transition implementation but left working-looking settings. The settings now state that wallpaper changes are instant. Stored transition preferences are preserved; animated transitions are not restored by this hardening patch.

The independent follow-up review found no blocker in these corrections and no expansion of permissions, networking or execution capabilities.

## Validation

- Full local macOS suite: **174 tests passed, 0 failures**, including six new regression tests.
- After the final weak-capture and settings text changes, the six playback regression tests were rerun successfully and the application rebuilt.
- New tests generate real short H.264 video and exercise both renderers: looping after a failed replacement, pause stability, and stopping before an asynchronous load attaches. Scheduler tests cover 500 concurrent requests and invalidated work across restart.
- Same four-second Thread Sanitizer harness before/after: original renderer reported **2 data-race warnings**; corrected renderer completed **292 iterations, 0 warnings, exit 0**. The harness calls real `play()`/`pause()`/`stop()` without loading media or opening a window.
- `git diff --check` passed. XcodeGen regenerated the project to register the new test file and normalize existing source references.

Full test command:

```sh
xcodebuild test \
  -project src/Wallnetic/Wallnetic.xcodeproj \
  -scheme Wallnetic -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/wallnetic-review-build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_ENTITLEMENTS= ENABLE_APP_SANDBOX=NO \
  DEBUG_INFORMATION_FORMAT=dwarf
```

Local evidence: `/private/tmp/wallnetic-playback-hardening-tests.log`, `/private/tmp/wallnetic-playback-hardening-final.log`, and `/private/tmp/wallnetic-pr238-audit/renderer-tsan{,-fixed}.log`.

These checks do not establish visual smoothness, seamless frame presentation, multi-monitor sleep/wake behavior or signed App Store sandbox behavior. Existing Swift concurrency and deprecated Core Video API warnings remain separate follow-up work.
