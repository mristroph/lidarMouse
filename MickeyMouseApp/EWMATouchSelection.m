//
//  EWMATouchSelection.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/28/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "EWMATouchSelection.h"
#import "TouchThresholdCalibration.h"

static const float kCurrentDistanceWeight = 0.3;

@implementation EWMATouchSelection {
    Lidar2DDistance touchDistance_;
}

#pragma mark - Package API

- (void)forEachTouchInDistanceData:(NSData *)distanceData do:(void (^)(NSUInteger, Lidar2DDistance))block {
    __block BOOL foundTouches = NO;
    Lidar2DDistance const *distances = distanceData.lidar2D_distances;

    [self.thresholdCalibration forEachTouchedSweepInDistanceData:distanceData do:^(NSRange sweepRange) {
        if (sweepRange.length < 3)
            return;
        foundTouches = YES;
        [self updateTouchDistanceWithDistances:distances sweepRange:sweepRange];
        block(sweepRange.location + sweepRange.length / 2, touchDistance_);
    }];

    if (!foundTouches) {
        touchDistance_ = -1.0;
    }
}

#pragma mark - Implementation details

- (void)updateTouchDistanceWithDistances:(Lidar2DDistance const *)distances sweepRange:(NSRange)sweepRange {
    ++sweepRange.location;
    sweepRange.length -= 2;
    Lidar2DDistance sum = 0;
    for (NSUInteger i = 0; i < sweepRange.length; ++i) {
        sum += distances[sweepRange.location + i];
    }

    Lidar2DDistance currentDistance = sum / sweepRange.length;
    touchDistance_ = (touchDistance_ > 0)
        ? kCurrentDistanceWeight * currentDistance + (1.0 - kCurrentDistanceWeight) * touchDistance_
        : currentDistance;
}

@end
