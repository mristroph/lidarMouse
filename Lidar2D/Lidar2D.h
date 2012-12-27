/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import <Foundation/Foundation.h>
#import "Lidar2DAncillary.h"

@protocol Lidar2DObserver;

@interface Lidar2D : NSObject

@property (nonatomic, readonly) NSString *devicePath;

// I start connecting to the device on a background thread.  I notify my observers when I have finished connecting.
- (void)connect;

// I start disconnecting from the device on a background thread.  I notify my observers when I have finished disconnecting.
- (void)disconnect;

// `YES` if I am currently connecting or disconnecting.
@property (nonatomic, readonly) BOOL isBusy;

// `YES` if I am fully connected to my device.  While I am connected, the device sends me distance measurements, which I forward to my observers.
@property (nonatomic, readonly) BOOL isConnected;

- (void)addObserver:(id<Lidar2DObserver>)observer;
- (void)removeObserver:(id<Lidar2DObserver>)observer;

// The serial number of the device.  Useful for distinguishing amongst multiple connected devices.  Only valid after `isConnected` becomes true.
@property (nonatomic, copy, readonly) NSString *serialNumber;

// The number of distinct angles at which the device measures distance.  The distances are equally-spaced around the arc of coverage.  Only valid after `isConnected` becomes true.
@property (nonatomic, readonly) NSUInteger rayCount;

// The size of the arc of coverage, in degrees.  The individual distances are evenly spaced around this arc.  This is the difference between the first distance angle and the last distance angle.  Only valid after `coverageDegrees` becomes true.
@property (nonatomic, readonly) double coverageDegrees;

// The offset in degrees of the first ray from horizontal to the right.
@property (nonatomic, readonly) double firstRayOffsetDegrees;

@end

@protocol Lidar2DObserver

// The device has been physically disconnected.  You should stop observing me and release your reference to me.
- (void)lidar2DDidTerminate:(Lidar2D *)device;

@optional

// I encountered an error.
- (void)lidar2d:(Lidar2D *)device didFailWithError:(NSError *)error;

// I finished connecting to the physical device.  Expect to receive `lidar2D:didReceiveDistances:` messages.
- (void)lidar2dDidConnect:(Lidar2D *)device;

// I finished disconnecting from the physical device.  You will stop receiving `lidar2D:didReceiveDistances:` messages very soon unless you send me `connect` again.
- (void)lidar2dDidDisconnect:(Lidar2D *)device;

// I received distance data from the device.  Use the `NSData+Lidar2D` category to access the distance values.
- (void)lidar2d:(Lidar2D *)device didReceiveDistanceData:(NSData *)distanceData;

@end
