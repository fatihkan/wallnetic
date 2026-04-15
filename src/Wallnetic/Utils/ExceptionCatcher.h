#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs the given block and returns any Objective-C exception it raises so
/// Swift callers can recover instead of aborting. Returns nil on success.
NSException * _Nullable WNCatchException(void (NS_NOESCAPE ^ _Nonnull block)(void));

NS_ASSUME_NONNULL_END
