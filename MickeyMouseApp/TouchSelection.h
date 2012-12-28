//
//  TouchSelection.h
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/28/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSData+Lidar2D.h"

@class TouchThresholdCalibration;

@interface TouchSelection : NSObject

@property (nonatomic, strong) TouchThresholdCalibration *thresholdCalibration;

- (void)forEachTouchInDistanceData:(NSData *)distanceData do:(void (^)(NSUInteger rayIndex, Lidar2DDistance distance))block;

@end
