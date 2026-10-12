#import <ScreenSaver/ScreenSaver.h>
#import <AVFoundation/AVFoundation.h>
#import "ProbeInspection.h"

// Research only: fixed bundled original video, no preferences, library paths,
// network, app group, executable downloads, or installation behavior.
@interface WNResearchScreenSaverView : ScreenSaverView <WNProbeInspection>
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@property(nonatomic, strong) AVPlayerLayer *videoLayer;
@property(nonatomic) BOOL requestedAnimation;
@property(nonatomic) BOOL displaySleeping;
@property(nonatomic, readwrite) NSUInteger playbackGeneration;
@end

@implementation WNResearchScreenSaverView
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
    // AVPlayer drives video. The superclass timer does not draw video frames.
    self.animationTimeInterval = 1.0;
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    [center addObserver:self selector:@selector(displayWillSleep:)
                   name:NSWorkspaceScreensDidSleepNotification object:nil];
    [center addObserver:self selector:@selector(displayDidWake:)
                   name:NSWorkspaceScreensDidWakeNotification object:nil];
}

- (void)startAnimation {
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

- (void)displayWillSleep:(NSNotification *)notification {
    self.displaySleeping = YES;
    [self reconcilePlayback];
}

- (void)displayDidWake:(NSNotification *)notification {
    self.displaySleeping = NO;
    [self reconcilePlayback];
}

- (void)reconcilePlayback {
    if (!self.requestedAnimation || self.displaySleeping || self.window == nil) {
        [self releasePlayback];
        [super stopAnimation];
        return;
    }
    if (self.player != nil) { return; }
    NSURL *sample = [[NSBundle bundleForClass:self.class] URLForResource:@"AuroraSample" withExtension:@"mp4"];
    if (sample == nil) { return; } // Black fallback; never look outside our bundle.
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:sample];
    self.player = [AVQueuePlayer queuePlayerWithItems:@[]];
    self.player.muted = YES;
    self.player.preventsDisplaySleepDuringVideoPlayback = NO;
    self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];
    self.videoLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.videoLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.videoLayer.frame = self.bounds;
    [self.layer addSublayer:self.videoLayer];
    self.playbackGeneration += 1;
    [super startAnimation];
    [self.player play];
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
- (BOOL)readyForDisplay { return self.videoLayer.readyForDisplay; }
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
