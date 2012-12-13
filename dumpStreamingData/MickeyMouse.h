/*
Created by Rob Mayoff on 12/10/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import <Foundation/Foundation.h>

@protocol Lidar2DProxy;

@interface MickeyMouse : NSObject

- (id)initWithLidar2DProxy:(id<Lidar2DProxy>)proxy;

@end
