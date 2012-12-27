//
//  NSData+Lidar2D.h
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/26/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef float Lidar2DDistance;
#define Lidar2DDistance_Invalid HUGE_VALF

static inline BOOL isLidar2DDistanceValid(Lidar2DDistance distance) { return distance != Lidar2DDistance_Invalid; }

@interface NSData (Lidar2D)

@property (nonatomic, readonly) NSUInteger lidar2D_distanceCount;
@property (nonatomic, readonly) Lidar2DDistance const *lidar2D_distances;

@end
