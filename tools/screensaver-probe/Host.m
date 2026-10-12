#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>
#import "ProbeInspection.h"

static NSUInteger checks = 0;
static NSUInteger failures = 0;

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
        }
    }
    return condition();
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
        if (argc != 2) {
            fprintf(stderr, "Usage: ScreenSaverProbeHost /path/to/WallneticScreenSaverProbe.saver\n");
            return EXIT_FAILURE;
        }
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
            ![viewClass conformsToProtocol:@protocol(WNProbeInspection)]) {
            fprintf(stderr, "Unexpected principal class\n");
            return EXIT_FAILURE;
        }
        ScreenSaverView<WNProbeInspection> *preview = [[viewClass alloc]
            initWithFrame:NSMakeRect(0, 0, 320, 180) isPreview:YES];
        ScreenSaverView<WNProbeInspection> *second = [[viewClass alloc]
            initWithFrame:NSMakeRect(0, 0, 480, 270) isPreview:NO];
        if (preview == nil || second == nil) {
            fprintf(stderr, "Could not instantiate views\n");
            return EXIT_FAILURE;
        }
        Check(!preview.resourcesActive && !second.resourcesActive, @"No decoder before host start");
        NSWindow *firstWindow = MakeWindow(NSMakeRect(80, 140, 320, 180), @"Wallnetic research · preview", preview);
        NSWindow *secondWindow = MakeWindow(NSMakeRect(420, 140, 480, 270), @"Wallnetic research · second view", second);
        [preview startAnimation];
        [second startAnimation];
        Check(WaitUntil(8, ^BOOL {
            return preview.readyForDisplay && second.readyForDisplay &&
                CMTimeGetSeconds(preview.playbackTime) > 0.25 && CMTimeGetSeconds(second.playbackTime) > 0.25;
        }), @"Two independent AVPlayerLayer views decode and advance");
        Check(preview.isPreview && !second.isPreview, @"Preview argument retained in debug host");
        NSUInteger generation = preview.playbackGeneration;
        [preview startAnimation];
        Check(preview.playbackGeneration == generation, @"Repeated start does not allocate another decoder");
        Check(WaitUntil(9, ^BOOL { return preview.completedLoops >= 1 && second.completedLoops >= 1; }),
              @"Both six-second videos loop");
        [secondWindow setContentSize:NSMakeSize(360, 480)];
        [second layoutSubtreeIfNeeded];
        Check(CGSizeEqualToSize(second.videoBounds.size, CGSizeMake(360, 480)), @"Aspect-fill layer follows portrait resize");
        [preview stopAnimation];
        Check(!preview.resourcesActive && preview.playbackRate == 0 && !preview.isAnimating,
              @"Stop releases player, looper, layer and superclass timer");
        Check(second.resourcesActive && second.playbackRate > 0, @"Stopping one view preserves the other");
        [preview stopAnimation];
        Check(!preview.resourcesActive, @"Repeated stop is harmless");

        // In-process notifications only: this does not put the Mac to sleep.
        NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
        [center postNotificationName:NSWorkspaceScreensDidSleepNotification object:nil];
        Check(!second.resourcesActive && !second.isAnimating, @"Synthetic display sleep releases active resources");
        [center postNotificationName:NSWorkspaceScreensDidWakeNotification object:nil];
        Check(WaitUntil(5, ^BOOL { return second.readyForDisplay && second.playbackRate > 0; }),
              @"Synthetic wake resumes only the still-requested view");
        Check(!preview.resourcesActive, @"Wake does not resume a stopped view");
        [center postNotificationName:NSWorkspaceScreensDidSleepNotification object:nil];
        [second stopAnimation];
        [center postNotificationName:NSWorkspaceScreensDidWakeNotification object:nil];
        Check(!second.resourcesActive, @"Stop during sleep prevents wake from recreating a decoder");

        [preview startAnimation];
        [preview removeFromSuperview];
        Check(!preview.resourcesActive && !preview.isAnimating, @"Detaching view releases playback even without stop callback");
        [preview stopAnimation];
        firstWindow.contentView = preview;
        for (NSUInteger index = 0; index < 20; index++) {
            [preview startAnimation];
            [preview stopAnimation];
        }
        Check(!preview.resourcesActive && !preview.isAnimating, @"Twenty restart/stop cycles leave no active playback");
        __weak ScreenSaverView *weakView;
        @autoreleasepool {
            ScreenSaverView *disposable = [[viewClass alloc] initWithFrame:NSMakeRect(0, 0, 10, 10) isPreview:YES];
            weakView = disposable;
        }
        Check(weakView == nil, @"Workspace observers do not retain an unused view");
        [preview stopAnimation];
        [second stopAnimation];
        [firstWindow close];
        [secondWindow close];
        printf("RESULT: %lu checks, %lu failures\n", (unsigned long)checks, (unsigned long)failures);
        return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
    }
}
