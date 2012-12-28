//
//  MiddleRayTouchSelection.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/28/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "MiddleRayTouchSelection.h"
#import "TouchThresholdCalibration.h"

@implementation MiddleRayTouchSelection

- (void)forEachTouchInDistanceData:(NSData *)distanceData do:(void (^)(NSUInteger, Lidar2DDistance))block {
    Lidar2DDistance const *distances = distanceData.lidar2D_distances;
    [self.thresholdCalibration forEachTouchedSweepInDistanceData:distanceData do:^(NSRange sweepRange) {
        NSUInteger middleRayIndex = sweepRange.location + sweepRange.length / 2;
        block(middleRayIndex, distances[middleRayIndex]);
    }];
}

@end
