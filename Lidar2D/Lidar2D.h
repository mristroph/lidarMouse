/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import <Foundation/Foundation.h>

@protocol Lidar2DObserver;

typedef uint32_t Lidar2DDistance;

@interface Lidar2D : NSObject

// I initialize myself to connect to the device at `path`.  I don't actually open the device until you send me `connect`.
- (id)initWithDevicePath:(NSString *)path;

@property (nonatomic, readonly) NSString *devicePath;

// I start connecting to the device on a background thread.  I notify my observers when I have finished connecting.
- (void)connect;

// I start disconnecting from the device on a background thread.  I notify my observers when I have finished disconnecting.
- (void)disconnect;

// `YES` if I am fully connected to my device.
@property (nonatomic, readonly) BOOL isConnected;

// I ask the device to start streaming distances to me.
- (void)startStreaming;

// I ask the device to stop streaming distances to me.
- (void)stopStreaming;

// `YES` if I expect the device to be sending me streaming data.
@property (nonatomic, readonly) BOOL isStreaming;

- (void)addObserver:(id<Lidar2DObserver>)observer;
- (void)removeObserver:(id<Lidar2DObserver>)observer;

// The serial number of the device.  Useful for distinguishing amongst multiple connected devices.  Only valid after `isConnected` becomes true.
@property (nonatomic, readonly) NSString *serialNumber;

// The number of distinct angles at which the device measures distance.  The distances are equally-spaced around the arc of coverage.  Only valid after `isConnected` becomes true.
@property (nonatomic, readonly) NSUInteger rayCount;

// The size of the arc of coverage, in degrees.  The individual distances are evenly spaced around this arc.  This is the difference between the first distance angle and the last distance angle.  Only valid after `coverageDegrees` becomes true.
@property (nonatomic, readonly) double coverageDegrees;

@end

@protocol Lidar2DObserver

@optional

// I encountered an error.
- (void)lidar2d:(Lidar2D *)device didFailWithError:(NSError *)error;

// I finished connecting to the physical device.
- (void)lidar2dDidConnect:(Lidar2D *)device;

// I finished disconnecting from the physical device.
- (void)lidar2dDidDisconnect:(Lidar2D *)device;

// I asked the device to start streaming distances.  You should expect to receive `lidar2D:didReceiveDistances:` messages.
- (void)lidar2DWillBeginStreaming:(Lidar2D *)device;

// I asked the device to stop streaming distances.  I will not send any more `lidar2D:didReceiveDistances:` messages until you send me `startStreaming` again.
- (void)lidar2DDidStopStreaming:(Lidar2D *)device;

// I received distance data from the device.  The `distances` array contains `device.rayCount` elements.
- (void)lidar2d:(Lidar2D *)device didReceiveDistances:(Lidar2DDistance const *)distances;

@end

extern NSString *const Lidar2DErrorDomain;
extern NSString *const Lidar2DErrorStatusKey;
extern NSString *const Lidar2DErrorExpectedStatusKey;
