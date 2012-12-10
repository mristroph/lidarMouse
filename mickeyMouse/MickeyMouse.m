/*
Created by Rob Mayoff on 12/10/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import "MickeyMouse.h"
#import "Lidar2D.h"

@implementation MickeyMouse {
    id<Lidar2DProxy> proxy_;
}

- (id)initWithLidar2DProxy:(id<Lidar2DProxy>)proxy {
    if ((self = [super init])) {
        proxy_ = proxy;
        [proxy_ performBlock:^(id<Lidar2D> device) {
            [self runWithDevice:device];
        }];
    }
    return self;
}

- (void)runWithDevice:(id<Lidar2D>)device {
    if (device.error) {
        NSLog(@"%@ error: %@", device, device.error);
        return;
    }

    [device forEachStreamingDataSnapshot:^(NSData *data, BOOL *stop) {
        *stop = NO;
        NSLog(@"data=%@", data);
    }];

    NSLog(@"%@ error: %@", device, device.error);
}

@end
