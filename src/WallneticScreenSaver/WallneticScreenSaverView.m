#import <ScreenSaver/ScreenSaver.h>
#import <AVFoundation/AVFoundation.h>
#import "PlaybackInspection.h"

// A standalone in-process plug-in. All media comes from this signed bundle;
// there is no Wallnetic library bridge, network, installer or shared state.
@interface WallneticScreenSaverView : ScreenSaverView <WNScreenSaverInspection>
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@property(nonatomic, strong) AVPlayerLayer *videoLayer;
@property(nonatomic) BOOL requestedAnimation;
@property(nonatomic) BOOL displaySleeping;
@property(nonatomic) BOOL systemSleeping;
@property(nonatomic, readwrite) BOOL playbackFailed;
@property(nonatomic, readwrite) NSUInteger playbackGeneration;
@property(nonatomic) CFTimeInterval lastProgressAt;
@property(nonatomic) CMTime lastPlaybackTime;
@end

@implementation WallneticScreenSaverView
- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)preview {
    self = [super initWithFrame:frame isPreview:preview];
    if (self) { [self configure]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) { [self configure]; }
    return self;
}

- (void)configure {
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.blackColor.CGColor;
    // AVFoundation presents the 30 fps video. The host's 1 Hz callback checks
    // decoder health; it never renders frames or starts another timer/thread.
    self.animationTimeInterval = 1.0;
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSString *name in @[NSWorkspaceScreensDidSleepNotification,
                            NSWorkspaceScreensDidWakeNotification,
                            NSWorkspaceWillSleepNotification,
                            NSWorkspaceDidWakeNotification]) {
        [center addObserver:self selector:@selector(workspaceStateChanged:) name:name object:nil];
    }
}

- (void)startAnimation {
    // A failed activation stays black until an explicit stop/start. Duplicate
    // start callbacks must not create a retry loop or a second decoder.
    if (!self.requestedAnimation) { self.playbackFailed = NO; }
    self.requestedAnimation = YES;
    [self reconcilePlayback];
}

- (void)stopAnimation {
    self.requestedAnimation = NO;
    [self releasePlayback];
    [super stopAnimation];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self reconcilePlayback];
}

- (void)workspaceStateChanged:(NSNotification *)notification {
    if (!NSThread.isMainThread) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf workspaceStateChanged:notification]; });
        return;
    }
    NSString *name = notification.name;
    if ([name isEqualToString:NSWorkspaceScreensDidSleepNotification]) { self.displaySleeping = YES; }
    else if ([name isEqualToString:NSWorkspaceScreensDidWakeNotification]) { self.displaySleeping = NO; }
    else if ([name isEqualToString:NSWorkspaceWillSleepNotification]) { self.systemSleeping = YES; }
    else if ([name isEqualToString:NSWorkspaceDidWakeNotification]) { self.systemSleeping = NO; }
    [self reconcilePlayback];
}

- (void)reconcilePlayback {
    if (!self.requestedAnimation || self.displaySleeping || self.systemSleeping ||
        self.window == nil || self.playbackFailed) {
        [self releasePlayback];
        [super stopAnimation];
        return;
    }
    if (self.player != nil) { return; }

    NSArray<NSString *> *names = @[@"lagoon", @"ember"];
    NSString *name = names[self.isPreview ? 0 : arc4random_uniform((uint32_t)names.count)];
    NSURL *media = [[NSBundle bundleForClass:WallneticScreenSaverView.class]
                   URLForResource:name withExtension:@"mp4"];
    NSDictionary *values = [media resourceValuesForKeys:@[NSURLIsRegularFileKey,
                                NSURLIsSymbolicLinkKey, NSURLFileSizeKey] error:nil];
    unsigned long long size = [values[NSURLFileSizeKey] unsignedLongLongValue];
    if (!media.isFileURL || ![values[NSURLIsRegularFileKey] boolValue] ||
        [values[NSURLIsSymbolicLinkKey] boolValue] || size == 0 || size > 2 * 1024 * 1024) {
        [self failPlayback];
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:media];
    self.player = [AVQueuePlayer queuePlayerWithItems:@[]];
    self.player.muted = YES;
    self.player.preventsDisplaySleepDuringVideoPlayback = NO;
    self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];
    self.videoLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.videoLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.videoLayer.frame = self.bounds;
    [self.layer addSublayer:self.videoLayer];
    self.playbackGeneration += 1;
    self.lastPlaybackTime = kCMTimeZero;
    self.lastProgressAt = CACurrentMediaTime();
    [super startAnimation];
    [self.player play];
}

- (void)animateOneFrame {
    if (self.player == nil) { return; }
    if (self.player.status == AVPlayerStatusFailed || self.looper.status == AVPlayerLooperStatusFailed ||
        self.player.currentItem.status == AVPlayerItemStatusFailed) {
        [self failPlayback];
        return;
    }
    CMTime time = self.player.currentTime;
    if (CMTIME_IS_NUMERIC(time) && CMTimeCompare(time, self.lastPlaybackTime) != 0) {
        self.lastPlaybackTime = time;
        self.lastProgressAt = CACurrentMediaTime();
    } else if (CACurrentMediaTime() - self.lastProgressAt >= 15.0) {
        // Missing callbacks are an OS-host release gate, not grounds to add a
        // private observer. With callbacks, a stalled decoder cannot retry forever.
        [self failPlayback];
    }
}

- (void)failPlayback {
    self.playbackFailed = YES;
    [self releasePlayback];
    [super stopAnimation];
}

- (void)releasePlayback {
    [self.player pause];
    [self.looper disableLooping];
    [self.player removeAllItems];
    self.videoLayer.player = nil;
    [self.videoLayer removeFromSuperlayer];
    self.videoLayer = nil;
    self.looper = nil;
    self.player = nil;
}

- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.videoLayer.frame = self.bounds;
    [CATransaction commit];
}

- (BOOL)resourcesActive { return self.player != nil && self.looper != nil && self.videoLayer != nil; }
- (BOOL)resourcesReleased { return self.player == nil && self.looper == nil && self.videoLayer == nil; }
- (BOOL)readyForDisplay { return self.videoLayer.readyForDisplay; }
- (BOOL)muted { return self.player.muted; }
- (BOOL)preventsDisplaySleep { return self.player.preventsDisplaySleepDuringVideoPlayback; }
- (float)playbackRate { return self.player.rate; }
- (CMTime)playbackTime { return self.player != nil ? self.player.currentTime : kCMTimeZero; }
- (NSInteger)completedLoops { return self.looper.loopCount; }
- (CGRect)videoBounds { return self.videoLayer.bounds; }

- (void)dealloc {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.player pause];
    [self.looper disableLooping];
    [self.player removeAllItems];
    self.videoLayer.player = nil;
    [self.videoLayer removeFromSuperlayer];
}
@end
