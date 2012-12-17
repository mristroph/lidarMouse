//
//  RawDataGraphView.h
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Lidar2D;

@interface RawDataGraphView : NSView

@property (nonatomic, strong) Lidar2D *device;
@property (nonatomic, copy) NSData *untouchedDistances;
@property (nonatomic, copy) NSData *data;

@end
