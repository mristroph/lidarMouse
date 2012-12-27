//
//  TouchCalibration.h
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/27/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSData+Lidar2D.h"

@protocol TouchCalibrationDelegate;
@class TouchThresholdCalibration;

@interface TouchCalibration : NSObject

@property (nonatomic, weak) id<TouchCalibrationDelegate> delegate;

// The `thresholdCalibration` must be ready before you start using me.
@property (nonatomic, strong) TouchThresholdCalibration *thresholdCalibration;

// Set this based on the device.  It's the coverage angle divided by the number of rays measured.
@property (nonatomic) double radiansPerRay;

// `YES` if I have calibrated enough touches.  `NO` if I need to calibrate another touch.
@property (nonatomic, readonly) BOOL ready;

// I throw away my calibration data and set `ready` to `NO`.
- (void)reset;

// I prepare to calibrate a touch at the given screen position.
- (void)startCalibratingTouchAtScreenPoint:(CGPoint)screenPoint;

@property (nonatomic, readonly) CGPoint currentCalibrationScreenPoint;

// I update my calibration data with the given distance data.  If this gives me enough data to calibrate the current touch, I do so and send `didFinishCalibrationWithResult:` to my delegate.  If, after doing so, I have calibrated enough touches, I set `ready` to `YES`.
- (void)calibrateWithDistanceData:(NSData *)data;

// I return the point in screen coordinates corresponding to the given sensor data. 
- (CGPoint)screenPointForRayIndex:(NSUInteger)rayIndex distance:(Lidar2DDistance)distance;

@end

@protocol TouchCalibrationDelegate <NSObject>

- (void)touchCalibrationDidFailWithNoTouches;
- (void)touchCalibrationDidFailWithMultipleTouches;
- (void)touchCalibrationDidSucceed;

@end
