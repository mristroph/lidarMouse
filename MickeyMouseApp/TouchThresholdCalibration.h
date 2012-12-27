//
//  TouchThresholdCalibration.h
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/26/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TouchThresholdCalibration : NSObject

@property (nonatomic, readonly) BOOL ready;

// I throw away my calibration data and set `ready` to `NO`.
- (void)reset;

// I update my calibration data with the given distance data.  If, after doing so, I have enough calibration data, I set `ready` to `YES`.
- (void)calibrateWithDistanceData:(NSData *)data;

// Scan the given distance data for each contiguous range of rays that has distances shorter than my calibrated distances.  Call `block` once for each such range.
- (void)forEachTouchedSweepInDistanceData:(NSData *)data do:(void (^)(NSRange sweepRange))block;

// FOR DEBUGGING ONLY
- (void)getTouchThresholdDistancesWithBlock:(void (^)(Lidar2DDistance const *distances, NSUInteger count))block;

@end
