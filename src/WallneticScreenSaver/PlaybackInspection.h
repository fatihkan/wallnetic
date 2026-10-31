#import <AppKit/AppKit.h>
#import <CoreMedia/CoreMedia.h>

// Internal, read-only observations for the separate development host. No setters,
// alternate media URLs, preferences or test-only behavior in the candidate.
@protocol WNScreenSaverInspection <NSObject>
@property(nonatomic, readonly) BOOL resourcesActive;
@property(nonatomic, readonly) BOOL resourcesReleased;
@property(nonatomic, readonly) BOOL playbackFailed;
@property(nonatomic, readonly) BOOL readyForDisplay;
@property(nonatomic, readonly) BOOL muted;
@property(nonatomic, readonly) BOOL preventsDisplaySleep;
@property(nonatomic, readonly) float playbackRate;
@property(nonatomic, readonly) CMTime playbackTime;
@property(nonatomic, readonly) NSInteger completedLoops;
@property(nonatomic, readonly) NSUInteger playbackGeneration;
@property(nonatomic, readonly) CGRect videoBounds;
@end
