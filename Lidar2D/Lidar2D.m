/*
 Created by Rob Mayoff on 12/8/12.
 Copyright (c) 2012 Rob Mayoff. All rights reserved.
 */

#import "DqdObserverSet.h"
#import "Lidar2D.h"
#import "Lidar2DConnection.h"

@interface Lidar2D () <Lidar2DConnectionDelegate>
@end

@implementation Lidar2D {
    DqdObserverSet *observers_;
    dispatch_queue_t queue_; // I use this to sequence changes to connection_.connectionState.  Blocks on this queue don't return until they have finished making the state changes.
    Lidar2DConnection *connection_;
}

#pragma mark - Public API

- (void)dealloc {
    if (connection_) {
        Lidar2DConnection *connection = connection_; // prevent block from retaining me
        dispatch_async(queue_, ^{
            [connection disconnect];
        });
    }

    // queue_ retains itself if I just put a block on it, and releases itself when the block returns.
    dispatch_release(queue_);
}

- (id)initWithDevicePath:(NSString *)path {
    if ((self = [super init])) {
        _devicePath = [path copy];
        queue_ = dispatch_queue_create([[NSString stringWithFormat:@"com.dqd.Lidar2D-%s", path.fileSystemRepresentation] UTF8String], 0);
        observers_ = [[DqdObserverSet alloc] initWithProtocol:@protocol(Lidar2DObserver)];
    }
    return self;
}

@synthesize devicePath = _devicePath;

- (void)connect {
    dispatch_async(queue_, ^{
        if (connection_)
            return;
        connection_ = [[Lidar2DConnection alloc] initWithDevicePath:_devicePath delegate:self];
        if (connection_) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [observers_.proxy lidar2dDidConnect:self];
            });
        }
    });
}

- (void)disconnect {
    dispatch_async(queue_, ^{
        if (!connection_)
            return;
        [connection_ disconnect];
        connection_ = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [observers_.proxy lidar2dDidDisconnect:self];
        });
    });
}

- (BOOL)isConnected {
    return connection_ != nil;
}

- (void)addObserver:(id<Lidar2DObserver>)observer {
    [observers_ addObserver:observer];
}

- (void)removeObserver:(id<Lidar2DObserver>)observer {
    [observers_ removeObserver:observer];
}

- (NSString *)serialNumber {
    return connection_.serialNumber;
}

- (NSUInteger)rayCount {
    return connection_.rayCount;
}

- (double)coverageDegrees {
    return connection_.coverageDegrees;
}

#pragma mark - Lidar2DConnectionDelegate protocol

- (void)connection:(Lidar2DConnection *)connection didFailWithError:(NSError *)error {
    (void)connection;
    dispatch_async(dispatch_get_main_queue(), ^{
        [observers_.proxy lidar2d:self didFailWithError:error];
    });
}

- (void)connection:(Lidar2DConnection *)connection didReceiveDistances:(const Lidar2DDistance *)distances {
    (void)connection;
    NSData *data = [[NSData alloc] initWithBytes:distances length:connection.rayCount * sizeof *distances];
    dispatch_async(dispatch_get_main_queue(), ^{
        [observers_.proxy lidar2d:self didReceiveDistances:data.bytes];
    });
}

@end


