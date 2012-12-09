/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import "Lidar2D.h"

@interface Lidar2DDevice : NSObject <Lidar2D, Lidar2DProxy>

- (id)initWithDevicePath:(NSString *)path;

@property (nonatomic, readonly) NSString *devicePath;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, readonly) NSString *serialNumber;

@end
