//
//  TouchSelection.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/28/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "TouchSelection.h"

@implementation TouchSelection

@synthesize thresholdCalibration = _thresholdCalibration;

- (void)forEachTouchInDistanceData:(NSData *)distanceData do:(void (^)(NSUInteger, Lidar2DDistance))block {
    (void)distanceData;
    (void)block;
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

@end
