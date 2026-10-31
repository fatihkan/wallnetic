#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>
#import <AVFoundation/AVFoundation.h>
#import "../../src/WallneticScreenSaver/PlaybackInspection.h"
#import <mach/mach.h>
#import <sys/resource.h>

static NSUInteger checks = 0;
static NSUInteger failures = 0;
static NSHashTable<ScreenSaverView *> *hostedViews;
static NSTimeInterval lastHostTick = 0;

static void Check(BOOL condition, NSString *message) {
    checks += 1;
    if (!condition) { failures += 1; }
    printf("%s: %s\n", condition ? "PASS" : "FAIL", message.UTF8String);
    fflush(stdout);
}

static BOOL WaitUntil(NSTimeInterval timeout, BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        @autoreleasepool {
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
                inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event != nil) { [NSApp sendEvent:event]; }
            [NSApp updateWindows];
            // Emulate the public host's 1 Hz animation callback, not video drawing.
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            if (now - lastHostTick >= 1) {
                lastHostTick = now;
                for (ScreenSaverView *view in hostedViews) {
                    if (view.isAnimating) { [view animateOneFrame]; }
                }
            }
        }
    }
    return condition();
}

static double CPUSeconds(void) {
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    return usage.ru_utime.tv_sec + usage.ru_stime.tv_sec +
           (usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000000.0;
}

static uint64_t FootprintBytes(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) { return 0; }
    return info.phys_footprint;
}

static void Measure(NSString *phase, NSTimeInterval duration) {
    double cpu = CPUSeconds();
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    WaitUntil(duration, ^BOOL { return NO; });
    NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - start;
    printf("METRIC: %s duration_s=%.2f cpu_percent_one_core=%.3f footprint_bytes=%llu\n",
           phase.UTF8String, elapsed, 100.0 * (CPUSeconds() - cpu) / elapsed,
           (unsigned long long)FootprintBytes());
    fflush(stdout);
}

static NSWindow *MakeWindow(NSRect frame, NSString *title, NSView *view) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.title = title;
    window.contentView = view;
    [window orderFront:nil];
    return window;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || argc > 3 || (argc == 3 && strcmp(argv[2], "--expect-fallback") != 0 &&
                                    strcmp(argv[2], "--benchmark") != 0)) {
            fprintf(stderr, "Usage: ScreenSaverProbeHost /path/to/WallneticScreenSaver.saver [--expect-fallback|--benchmark]\n");
            return EXIT_FAILURE;
        }
        BOOL expectFallback = argc == 3 && strcmp(argv[2], "--expect-fallback") == 0;
        BOOL benchmark = argc == 3 && strcmp(argv[2], "--benchmark") == 0;
        hostedViews = [NSHashTable weakObjectsHashTable];
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        NSURL *url = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
        NSBundle *bundle = [NSBundle bundleWithURL:url];
        NSError *error = nil;
        // The caller supplies our locally built research bundle. Never feed an
        // untrusted downloaded bundle to a development plug-in host.
        if (![bundle loadAndReturnError:&error]) {
            fprintf(stderr, "Bundle load failed: %s\n", error.localizedDescription.UTF8String);
            return EXIT_FAILURE;
        }
        Class viewClass = bundle.principalClass;
        if (![viewClass isSubclassOfClass:ScreenSaverView.class] ||
            ![viewClass conformsToProtocol:@protocol(WNScreenSaverInspection)]) {
            fprintf(stderr, "Unexpected principal class\n");
            return EXIT_FAILURE;
        }
        ScreenSaverView<WNScreenSaverInspection> *preview = [[viewClass alloc]
            initWithFrame:NSMakeRect(0, 0, 320, 180) isPreview:YES];
        ScreenSaverView<WNScreenSaverInspection> *second = [[viewClass alloc]
            initWithFrame:NSMakeRect(0, 0, 480, 270) isPreview:NO];
        if (preview == nil || second == nil) {
            fprintf(stderr, "Could not instantiate views\n");
            return EXIT_FAILURE;
        }
        [hostedViews addObject:preview];
        [hostedViews addObject:second];
        Check(preview.resourcesReleased && second.resourcesReleased, @"No decoder before host start");
        NSWindow *firstWindow = MakeWindow(NSMakeRect(80, 140, 320, 180), @"Wallnetic research · preview", preview);
        NSWindow *secondWindow = MakeWindow(NSMakeRect(420, 140, 480, 270), @"Wallnetic research · second view", second);
        if (benchmark) { Measure(@"idle_before", 8); }
        [preview startAnimation];
        [second startAnimation];
        if (expectFallback) {
            Check(WaitUntil(6, ^BOOL { return preview.playbackFailed && second.playbackFailed; }),
                  @"Invalid media reaches black fallback in both views");
            Check(preview.resourcesReleased && second.resourcesReleased && !preview.isAnimating && !second.isAnimating,
                  @"Fallback releases all playback resources and stops host animation");
            NSUInteger before = preview.playbackGeneration;
            [preview startAnimation];
            [NSWorkspace.sharedWorkspace.notificationCenter postNotificationName:NSWorkspaceScreensDidWakeNotification object:nil];
            Check(preview.playbackGeneration == before && preview.resourcesReleased,
                  @"Failure cannot cause repeated-start or wake retry loops");
            [preview stopAnimation];
            [second stopAnimation];
            [firstWindow close];
            [secondWindow close];
            printf("RESULT: %lu checks, %lu failures\n", (unsigned long)checks, (unsigned long)failures);
            return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
        }
        Check(WaitUntil(8, ^BOOL {
            return preview.readyForDisplay && second.readyForDisplay &&
                CMTimeGetSeconds(preview.playbackTime) > 0.25 && CMTimeGetSeconds(second.playbackTime) > 0.25;
        }), @"Two independent AVPlayerLayer views decode and advance");
        Check(preview.isPreview && !second.isPreview, @"Preview argument retained in debug host");
        Check(preview.muted && second.muted && !preview.preventsDisplaySleep && !second.preventsDisplaySleep,
              @"Both instances are muted and allow display sleep");
        NSUInteger generation = preview.playbackGeneration;
        [preview startAnimation];
        Check(preview.playbackGeneration == generation, @"Repeated start does not allocate another decoder");
        Check(WaitUntil(9, ^BOOL { return preview.completedLoops >= 1 && second.completedLoops >= 1; }),
              @"Both six-second videos loop");
        if (benchmark) { Measure(@"two_playing", 15); }
        [secondWindow setContentSize:NSMakeSize(360, 480)];
        [second layoutSubtreeIfNeeded];
        Check(CGSizeEqualToSize(second.videoBounds.size, CGSizeMake(360, 480)), @"Aspect-fill layer follows portrait resize");
        [preview stopAnimation];
        Check(preview.resourcesReleased && preview.playbackRate == 0 && !preview.isAnimating,
              @"Stop releases player, looper, layer and superclass timer");
        Check(second.resourcesActive && second.playbackRate > 0, @"Stopping one view preserves the other");
        [preview stopAnimation];
        Check(preview.resourcesReleased, @"Repeated stop is harmless");

        // In-process notifications only: this does not put the Mac to sleep.
        NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
        [center postNotificationName:NSWorkspaceScreensDidSleepNotification object:nil];
        Check(second.resourcesReleased && !second.isAnimating, @"Synthetic display sleep releases active resources");
        [center postNotificationName:NSWorkspaceWillSleepNotification object:nil];
        [center postNotificationName:NSWorkspaceScreensDidWakeNotification object:nil];
        Check(second.resourcesReleased, @"Display wake cannot override system sleep");
        [center postNotificationName:NSWorkspaceScreensDidSleepNotification object:nil];
        [center postNotificationName:NSWorkspaceDidWakeNotification object:nil];
        Check(second.resourcesReleased, @"System wake cannot override display sleep");
        [center postNotificationName:NSWorkspaceScreensDidWakeNotification object:nil];
        Check(WaitUntil(5, ^BOOL { return second.readyForDisplay && second.playbackRate > 0; }),
              @"Synthetic wake resumes only the still-requested view");
        Check(preview.resourcesReleased, @"Wake does not resume a stopped view");
        [center postNotificationName:NSWorkspaceScreensDidSleepNotification object:nil];
        [second stopAnimation];
        [center postNotificationName:NSWorkspaceScreensDidWakeNotification object:nil];
        Check(second.resourcesReleased, @"Stop during sleep prevents wake from recreating a decoder");

        [preview startAnimation];
        [preview removeFromSuperview];
        Check(preview.resourcesReleased && !preview.isAnimating, @"Detaching view releases playback even without stop callback");
        firstWindow.contentView = preview;
        Check(preview.resourcesActive, @"Reattaching a still-requested view recreates playback");
        [preview stopAnimation];
        [preview removeFromSuperview];
        firstWindow.contentView = preview;
        Check(preview.resourcesReleased, @"Reattaching a stopped view does not resume playback");
        for (NSUInteger index = 0; index < 20; index++) {
            [preview startAnimation];
            [preview stopAnimation];
        }
        Check(preview.resourcesReleased && !preview.isAnimating, @"Twenty restart/stop cycles leave no active playback");
        __weak ScreenSaverView *weakView;
        @autoreleasepool {
            ScreenSaverView *disposable = [[viewClass alloc] initWithFrame:NSMakeRect(0, 0, 10, 10) isPreview:YES];
            weakView = disposable;
        }
        Check(weakView == nil, @"Workspace observers do not retain an unused view");
        __weak ScreenSaverView *usedView;
        @autoreleasepool {
            ScreenSaverView *disposable = [[viewClass alloc] initWithFrame:NSMakeRect(0, 0, 100, 100) isPreview:YES];
            NSWindow *temporary = MakeWindow(NSMakeRect(50, 50, 100, 100), @"Wallnetic lifecycle check", disposable);
            [disposable startAnimation];
            [disposable stopAnimation];
            [disposable removeFromSuperview];
            [temporary close];
            usedView = disposable;
        }
        Check(usedView == nil, @"A used and dismissed view is deallocated");
        if (benchmark) { Measure(@"stopped_after", 8); }
        [preview startAnimation];
        Check(WaitUntil(5, ^BOOL { return preview.readyForDisplay && CMTimeGetSeconds(preview.playbackTime) > 0.25; }),
              @"A new activation starts after repeated teardown");
        // Fault injection in the external test host only: stop progression of
        // the real queue to exercise the candidate's bounded stall supervision.
        [(AVQueuePlayer *)[preview valueForKey:@"player"] pause];
        Check(WaitUntil(18, ^BOOL { return preview.playbackFailed; }) && preview.resourcesReleased,
              @"A stalled decoder times out and releases resources");
        NSUInteger failedGeneration = preview.playbackGeneration;
        [preview startAnimation];
        Check(preview.resourcesReleased && preview.playbackGeneration == failedGeneration,
              @"Duplicate start cannot retry a stalled activation");
        [preview stopAnimation];
        [preview startAnimation];
        Check(WaitUntil(5, ^BOOL { return preview.readyForDisplay && preview.playbackRate > 0; }) && !preview.playbackFailed,
              @"Explicit stop/start recovers a failed activation");
        [preview stopAnimation];
        [second stopAnimation];
        [firstWindow close];
        [secondWindow close];
        printf("RESULT: %lu checks, %lu failures\n", (unsigned long)checks, (unsigned long)failures);
        return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
    }
}
