/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import <Foundation/Foundation.h>
#import "Lidar2DAncillary.h"

@protocol Lidar2DObserver;

@interface Lidar2D : NSObject

// I initialize myself to connect to the device at `devicePath`.  I don't actually open the device until you send me `connect`.
- (id)initWithDevicePath:(NSString *)devicePath;

@property (nonatomic, readonly) NSString *devicePath;

// I start connecting to the device on a background thread.  I notify my observers when I have finished connecting.
- (void)connect;

// I start disconnecting from the device on a background thread.  I notify my observers when I have finished disconnecting.
- (void)disconnect;

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

@end

@protocol Lidar2DObserver

@optional

// I encountered an error.
- (void)lidar2d:(Lidar2D *)device didFailWithError:(NSError *)error;

// I finished connecting to the physical device.  Expect to receive `lidar2D:didReceiveDistances:` messages.
- (void)lidar2dDidConnect:(Lidar2D *)device;

// I finished disconnecting from the physical device.  You will stop receiving `lidar2D:didReceiveDistances:` messages very soon unless you send me `connect` again.
- (void)lidar2dDidDisconnect:(Lidar2D *)device;

// I received distance data from the device.  The `distances` array contains `device.rayCount` elements.
- (void)lidar2d:(Lidar2D *)device didReceiveDistances:(Lidar2DDistance const *)distances;

@end
