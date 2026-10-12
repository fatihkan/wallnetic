#import <AppKit/AppKit.h>
#import <CoreMedia/CoreMedia.h>

// Read-only observations used by the isolated development host, not a public API.
@protocol WNProbeInspection <NSObject>
@property(nonatomic, readonly) BOOL resourcesActive;
@property(nonatomic, readonly) BOOL readyForDisplay;
@property(nonatomic, readonly) float playbackRate;
@property(nonatomic, readonly) CMTime playbackTime;
@property(nonatomic, readonly) NSInteger completedLoops;
@property(nonatomic, readonly) NSUInteger playbackGeneration;
@property(nonatomic, readonly) CGRect videoBounds;
@end
