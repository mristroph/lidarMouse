/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import "Application.h"
#import "Lidar2D.h"
#import "Lidar2DManager.h"
#import "MickeyMouse.h"

@interface Application () <Lidar2DManagerDelegate>
@end

@implementation Application {
    Lidar2DManager *lidar2DManager_;
}

- (id)init {
    if ((self = [super init])) {
        lidar2DManager_ = [[Lidar2DManager alloc] init];
        lidar2DManager_.delegate = self;
        [lidar2DManager_ start];
    }
    return self;
}

#pragma mark - Lidar2DManagerDelegate protocol

- (void)lidar2DManager:(Lidar2DManager *)manager didReceiveError:(NSError *)error {
    (void)manager;
    NSLog(@"error: Lidar2DManager: %@", error);
    exit(1);
}

- (void)lidar2DManager:(Lidar2DManager *)manager didConnectToDevice:(id<Lidar2DProxy>)device {
    NSLog(@"Lidar2DManager %@ connected device %@", manager, device);
    (void)[[MickeyMouse alloc] initWithLidar2DProxy:device];
}

@end
