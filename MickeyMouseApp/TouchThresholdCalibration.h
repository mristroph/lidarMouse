//
//  TouchThresholdCalibration.h
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/26/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TouchThresholdCalibrationDelegate;

@interface TouchThresholdCalibration : NSObject

@property (nonatomic, weak) id<TouchThresholdCalibrationDelegate> delegate;
@property (nonatomic, readonly) BOOL ready;

// I throw away my calibration data and set `ready` to `NO`.
- (void)reset;

// I update my calibration data with the given distance data.  If, after doing so, I have enough calibration data, I set `ready` to `YES`.  I send
- (void)calibrateWithDistanceData:(NSData *)data;

// Scan the given distance data for each contiguous range of rays that has distances shorter than my calibrated distances.  Call `block` once for each such range.
- (void)forEachTouchedSweepInDistanceData:(NSData *)data do:(void (^)(NSRange sweepRange))block;

// My calibration data as a property list, suitable for passing to `updateWithDataPropertyList:`.
- (id)dataPropertyList;

// Restore my calibration data from `plist`, which must have been returned by `dataPropertyList`.
- (void)restoreDataPropertyList:(id)plist;

@end

@protocol TouchThresholdCalibrationDelegate <NSObject>

- (void)touchThresholdCalibration:(TouchThresholdCalibration *)calibration didUpdateThresholds:(Lidar2DDistance const *)thresholds count:(NSUInteger)count;

@end
