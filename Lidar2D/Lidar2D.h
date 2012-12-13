/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import <Foundation/Foundation.h>

@protocol Lidar2D <NSObject>

@property (nonatomic, readonly) NSString *devicePath;

// This is an error I have encountered, or nil.  Set this to nil after handling the error if you want to try to keep using me.
@property (nonatomic, strong) NSError *error;

// The serial number of the device.  Useful for distinguishing amongst multiple connected devices.
@property (nonatomic, readonly) NSString *serialNumber;

// The number of distinct angles at which the device measures distance.  The measurements are equally-spaced around the arc of coverage.
@property (nonatomic, readonly) NSUInteger rayCount;

// The size of the arc of coverage, in degrees.  The individual measurements are evenly spaced around this arc.  This is the difference between the first measurement angle and the last measurement angle.
@property (nonatomic, readonly) double coverageDegrees;

// I call the data snapshot block with a pointer to the distances detected by the device.  The `distances` array contains `rayCount` elements.
typedef void (^Lidar2DDataSnapshotBlock)(uint32_t const *distances, BOOL *stop);

// I ask the device to send me sensor data continuously.  Each time I receive a complete snapshot, I call `block`.  If `block` sets `*stop` to YES, I tell the device to stop sending me data and return.  If I encounter an error, I tell the device to stop sending me data and return.  Check `error` after I return.
- (void)forEachStreamingDataSnapshot:(Lidar2DDataSnapshotBlock)block;

@end

@protocol Lidar2DProxy <NSObject>

// Execute `block` asynchronously on this device's private serial queue.
- (void)performBlock:(void (^)(id<Lidar2D> device))block;

// Execute `block` synchronously on this device's private serial queue.
- (void)performBlockAndWait:(void (^)(id<Lidar2D> device))block;

@end

extern NSString *const Lidar2DErrorDomain;
extern NSString *const Lidar2DErrorStatusKey;
extern NSString *const Lidar2DErrorExpectedStatusKey;
