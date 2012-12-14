//
//  RawDataWindowController.h
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Lidar2D;

@interface RawDataWindowController : NSWindowController

- (id)initWithLidar2D:(Lidar2D *)device;

@end
