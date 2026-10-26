# Screen saver and live lock-screen feasibility

Research issue: [#259](https://github.com/fatihkan/wallnetic/issues/259), following
#84. Checked **2026-10-12** against current public Apple documentation, the local
macOS 26.4 SDK in Xcode 26.4 (17E192), and macOS 26.6.2 (25G83) on Apple Silicon.
This is a decision record and isolated prototype, not a shipping feature or a
claim that older/newer OS releases were physically tested.

Follow-up: #274 now has a [standalone development candidate](STANDALONE_SCREEN_SAVER.md).
The development host was migrated to test that candidate directly. The prototype
results below describe the original #259 experiment, preserved in #275; they do
not establish the candidate's outstanding physical/signed release gates.

## Decision

| Surface / route | Decision | Reason and next step |
| --- | --- | --- |
| Standalone `.saver` with bundled original videos, distributed separately | **Conditional go for a bounded implementation** | Public ScreenSaverView + AVFoundation path; prototype passed. Actual Apple host behavior and signed/notarized install, update and removal are mandatory gates before distribution. |
| Installing a companion `.saver` from the Mac App Store application | **No-go for the proposed design** | It writes executable code to a separate screen-saver installation location; the App Store packaging rules and host-owned access model do not provide a validated route. Keep the Store app self-contained. |
| Automatically reading the live Wallnetic library / current selection from the system screen-saver host | **No-go with the existing bridge** | A preferences suite/path is not a file-access grant; the plug-in cannot assign Wallnetic's App Group entitlements to Apple's host. No validated shared-media transport was found. |
| Arbitrary live wallpaper behind the system lock/login authentication UI | **No-go with the APIs identified** | No documented video-background registration API, extension point or entitlement was identified for this surface. Do not substitute private wallpaper stores or security changes. |
| Existing still-frame system wallpaper sync | **Keep** | Public image-setting API; useful fallback. macOS controls how it appears on the lock screen, in Spaces and Mission Control. |

The no-go findings describe this researched design and evidence, not proof that
Apple can never add an API. A screen saver may be visible while a password is
required according to OS settings; that is **not** a separate API to place our
chosen video behind every lock/login UI or promise a seamless desktop transition.
A newer public SDK/API or a documented Apple-supported route can reopen the
relevant decision. No live lock-screen prototype was built because there was no
supported integration path to test.

## Public API, OS and packaging boundaries

| Capability | Public API / packaging | Documented minimum | Proposed floor / constraints |
| --- | --- | --- | --- |
| Screen saver view and lifecycle | ScreenSaver.framework, ScreenSaverView, `.saver` bundle | macOS 10.0 | macOS 13, matching Wallnetic's floor; native arm64 and x86_64 required |
| Native video presentation | AVPlayerLayer | macOS 10.7 | One independent muted player per view; bounded original local media |
| Looping video | AVQueuePlayer + AVPlayerLooper | Looper: macOS 10.12 | Superclass lifecycle plus explicit player/looper teardown |
| Saver-specific preferences, if later needed | ScreenSaverDefaults | Legacy ScreenSaver framework | Owned by the host context; not a shared-library authorization mechanism |
| Desktop still-frame fallback | NSWorkspace.setDesktopImageURL | macOS 10.6 | Main thread; file URL to an image; no lock-screen video registration |
| Share a container between our own entitled executables | App Groups entitlement | macOS 10.7 | Does not make Apple's screen-saver host a member of Wallnetic's group |
| Live system lock-screen video | No supported registration API identified | Not applicable | No entitlement or minimum OS claimed |

Apple documents `.saver` bundles containing a ScreenSaverView subclass and the
start/stop lifecycle. Both architectures matter because the plug-in runs inside
a native host. The documented format is a bundle, **not** a third-party modern
`.appex` screen-saver extension point. [Screen Saver framework](https://developer.apple.com/documentation/screensaver),
[ScreenSaverView](https://developer.apple.com/documentation/screensaver/screensaverview),
[ScreenSaverDefaults](https://developer.apple.com/documentation/screensaver/screensaverdefaults).

AVFoundation supplies the video layer and native looping primitive used by the
probe. Their availability supports a macOS 13 deployment floor; it does not
establish OS-host compatibility. [AVPlayerLayer](https://developer.apple.com/documentation/avfoundation/avplayerlayer),
[AVPlayerLooper](https://developer.apple.com/documentation/avfoundation/avplayerlooper).

The image-setting API accepts a local image for a particular screen on the main
thread. It does not specify a video source or independently manage the secure
lock-screen background. The lock-screen no-go is our inference from the reviewed
public API/extension documentation and SDK, not an Apple statement that all future
implementations are impossible. [NSWorkspace.setDesktopImageURL](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:)).

## Media access and entitlements

The probe reads only its own bundled original sample and requests **no additional
entitlements**, App Groups, preferences, user files or network access. An in-process
plug-in uses the host process's entitlements; adding a claim to the plug-in cannot
turn the Apple-owned host into our entitled companion application. This is why
moving a file into `group.com.wallnetic.shared` does not by itself solve screen
saver media access. [Apple's plug-in entitlement guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups).

Wallnetic itself declares App Sandbox, `group.com.wallnetic.shared` and selected
file read/write access. Its imported video path can reside in its private
container. The actual saver host has a different identity/access context. Modern
macOS also protects app containers: a known path and POSIX readability alone are
not proof of access. User-selected URLs and scoped bookmarks must be handled in
the actual consuming process; a copied string or arbitrary UserDefaults suite
is insufficient. [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

There is deliberately no fallback that probes another app's container, writes the
legacy host's private preferences, broadens file access, or bypasses user consent.
An export/import design for user videos would require its own proven host-side
access/persistence model and privacy review before implementation. It is excluded
from the feasible first scope; bundled original videos avoid that dependency.

## Current repository findings and preserved fallback

- The unwired `ScreenSaverBridge.swift` placeholder has been removed (#306). It
  had no callers and no shipped `.saver` target. It wrote wallpaper/library paths
  to `UserDefaults(suiteName: "com.wallnetic.screensaver")`, which is not a
  verified App Group channel and does not grant the host access. The bundled-media
  candidate does not read that suite, and no caller or installer replaces it.
- The Xcode app targets remain the main application, widget and tests. The probe
  is outside those targets and only built separately by a development script/CI.
- `DesktopOverlayController` draws a clock/control panel at desktop level. It
  is not a secure lock-screen video implementation. README's previous claim that
  only the Store build lacks lock-screen video was unsupported and is corrected.
- `SystemWallpaperSync` continues to extract JPEG stills, apply them via the
  public NSWorkspace API, and attempt original-image restoration when disabled.
  Only its explanation and the Settings copy change; its runtime logic,
  entitlements, application version and preferences are preserved.

Restoration has existing limits: it records image paths for connected displays,
not the entire system wallpaper configuration, all inactive Spaces or Apple's
animated wallpaper selection. A file that no longer exists cannot be restored.
Deleting an app does not execute an uninstall hook; users should disable sync
before removing the app if they want its recorded images restored. Do not promise
that removing the research `.saver` restores video-wallpaper settings: the probe
never changes those settings in the first place.

## Isolated prototype and observations

Source and commands: [tools/screensaver-probe](../tools/screensaver-probe/README.md).
A small Objective-C ScreenSaverView bundle and a separate native debug host use
only ScreenSaver, AppKit, AVFoundation, QuartzCore and CoreMedia. The media is the
original, MIT-licensed 1280 × 720 H.264 Aurora onboarding sample. No user media is
read. Apple DTS describes using a separate development host for ScreenSaverView
work; we used that approach without installing or killing any system host.
[Apple DTS on a debug host](https://developer.apple.com/forums/thread/745327).

Observed on the machine above:

| Check | Result |
| --- | --- |
| Universal bundle and debug-host compilation | arm64 + x86_64; macOS 13 deployment target; warnings treated as errors |
| Bundle principal class and ad-hoc signature verification | Passed; no entitlements supplied; not a Developer ID/notarization result |
| Native video decode and advancement in two ordinary windows | Passed for both instances, including preview YES/NO input |
| At least one complete six-second loop per instance | Passed |
| Portrait resize and independent stop | Passed |
| Duplicate start/stop, release on stop and view detachment | Passed |
| Synthetic screen sleep/wake and stop-during-sleep behavior | Passed; no actual machine sleep or lock was triggered |
| Twenty start/stop cycles and observer lifetime | Passed |
| Total debug-host assertions | **16 passed, zero failures** |
| Existing application test suite after the documentation/Settings changes | **349 passed, zero failures**; ad-hoc signing, sandbox disabled, current local architecture |

Every run creates a unique ignored `.build/screensaver-probe.XXXXXX` directory.
There is no installation, shared-container change, host preference write or
system wallpaper change to restore. These are ad-hoc developer artifacts, not a
new build of the shipping Wallnetic app. CI compiles the probe on Xcode 15.2;
windowed playback checks are performed locally.

**Not established by this probe:** loading in Apple's actual screen-saver host,
real multi-display topology or unplug/replug, physical sleep/wake/lock/unlock,
FileVault/login window, Intel runtime, other supported macOS versions, battery/
thermal cost, a signed sandbox, Gatekeeper install/update/removal, or App Review
acceptance. Two windows demonstrate independent instances, not physical
multi-monitor compatibility. Per-view state cannot fix an OS host that omits
lifecycle callbacks or supplies the wrong preview flag.

## Distribution, installation and lifecycle gates

**Mac App Store:** our proposed companion installation is a no-go. Guidelines
2.4.5(i), (ii), (iv) and (v) constrain sandboxing, self-contained packaging, extra
installed functionality and privilege elevation. The current research is not
an App Review approval or a plan to download an installer from inside the Store
app. Revisit only with a documented supported design and review clarification.
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility).

**Separate direct distribution:** a bounded `.saver` containing original media
has a public API path worth implementing. Before release, sign the plug-in with
Developer ID Application and distribute an appropriately signed/notarized
container; an installer package, if chosen, also needs the relevant Installer
identity. Validate the exact downloaded artifact under Gatekeeper. No disabling
library validation in Apple's host, root helper, quarantine removal or security
setting changes are acceptable. [Distributing software on macOS](https://developer.apple.com/macos/distribution/),
[Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

User-controlled installation/selection must use the supported system workflow.
Prefer the current user's installation scope; do not silently change their saver,
password delay, lock policy or desktop. For uninstall, have the user select a
different saver in System Settings and remove only the companion they installed.
The companion owns no shared preferences/media in the initial scope, so no
application library files are removal candidates. Prove these steps with a
signed artifact before promising a seamless uninstall/restore experience.

Physical release gates must cover independent displays, mirrored displays,
preview/fullscreen, resize, display reconnect, actual idle activation, screen
sleep, system sleep, wake, lock/unlock, fast user switching, repeated previews and
host reload after update. Track player count/CPU/GPU/memory after dismissal;
stop, detachment and sleep must release resources, and wake must not resurrect
an explicitly stopped instance. If the host breaks this contract and no public
mitigation exists, narrow OS support or stop the release rather than add a
private notification/process-killing workaround.

This host risk is concrete: Apple DTS acknowledged reports about screen saver
lifecycle/preview/multiple-display behavior during the macOS 26 beta cycle, and
continued to recommend requesting a modern extension API in March 2026. Those
reports are evidence of integration risk, **not proof those bugs persist on every
current patch**. The local debug host does not settle their current status.
[macOS 26 screen saver discussion](https://developer.apple.com/forums/thread/787444),
[March 2026 DTS response](https://developer.apple.com/forums/thread/820860).

## Bounded follow-up

Implementation candidate: [#274 — Standalone screen saver with bundled original videos](https://github.com/fatihkan/wallnetic/issues/274).

Proceed only with a separately distributed, bundled-media screen saver candidate:
production target/identifiers, a small rights-cleared resource set, native
lifecycle, explicit user installation/removal guidance, and the signed/physical
validation gates above. No library sync, auto-selection, network catalog,
lock-screen background replacement or Store installer is part of that task.
No live lock-screen implementation task is created without a supported API.
The current still-frame sync remains available while that work is evaluated.
