/*
Created by Rob Mayoff on 12/10/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import "Dumper.h"
#import "Lidar2D.h"

@interface Dumper () <Lidar2DObserver>
@end

@implementation Dumper {
    Dumper *myself_; // keep myself around while my device is connected
    Lidar2D *device_;
}

- (id)initWithLidar2D:(Lidar2D *)device {
    if ((self = [super init])) {
        device_ = device;
        myself_ = self;
        [device addObserver:self];
        [device connect];
    }
    return self;
}

- (void)dealloc {
    NSLog(@"%@ dealloc", self);
    [device_ removeObserver:self];
}

- (void)lidar2DDidTerminate:(Lidar2D *)device {
    NSLog(@"device %@ terminated", device);
    myself_ = nil;
}

- (void)lidar2dDidConnect:(Lidar2D *)device {
    NSLog(@"device %@ connected", device);
}

- (void)lidar2dDidDisconnect:(Lidar2D *)device {
    NSLog(@"device %@ disconnected", device);
}

- (void)lidar2d:(Lidar2D *)device didFailWithError:(NSError *)error {
    NSLog(@"device %@ failed with error %@", device, error);
    [device disconnect];
    myself_ = nil;
}

- (void)lidar2d:(Lidar2D *)device didReceiveDistances:(const Lidar2DDistance *)distances {
    NSMutableString *string = [[NSMutableString alloc] init];
    for (NSUInteger i = 0, l = device.rayCount; i < l; ++i) {
        [string appendFormat:@"%u ", distances[i]];
    }
    printf("device %s reported distances: %s\n", device.description.UTF8String, string.UTF8String);
}

@end
