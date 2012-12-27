//
//  NSData+Lidar2D.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/26/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "NSData+Lidar2D.h"

@implementation NSData (Lidar2D)

- (NSUInteger)lidar2D_distanceCount {
    return self.length / sizeof *self.lidar2D_distances;
}

- (Lidar2DDistance const *)lidar2D_distances {
    return self.bytes;
}

@end
