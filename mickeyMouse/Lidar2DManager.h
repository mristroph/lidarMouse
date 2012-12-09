/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import <Foundation/Foundation.h>

@protocol  Lidar2DManagerDelegate;
@protocol Lidar2DProxy;

@interface Lidar2DManager : NSObject

// Once I am started, I send messages to my delegate on the GCD main queue.
 @property (nonatomic, weak) id<Lidar2DManagerDelegate> delegate;

// I schedule myself to run on the current run loop in the default mode, if I'm not already scheduled.  I notify my delegate of any already-connected devices before returning.
- (void)start;

// I deschedule myself if I am scheduled.  I do this automatically if I am deallocated.
- (void)stop;

@property (nonatomic, readonly) BOOL isStarted;

@end


@protocol Lidar2DManagerDelegate <NSObject>

- (void)lidar2DManager:(Lidar2DManager *)manager didReceiveError:(NSError *)error;

- (void)lidar2DManager:(Lidar2DManager *)manager didConnectToDevice:(id<Lidar2DProxy>)device;

@end