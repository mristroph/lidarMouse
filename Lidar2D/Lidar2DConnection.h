//
//  Lidar2DConnection.h
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/14/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Lidar2DAncillary.h"

@protocol Lidar2DConnectionDelegate;

// Lidar2DConnection is private to the Lidar2D package.

@interface Lidar2DConnection : NSObject

// I open the device at `devicePath` and ask it to stream distances.  I block until I either finish successfully or fail.  If I fail, I notify `delegate` and return nil.
- (id)initWithDevicePath:(NSString *)devicePath delegate:(id<Lidar2DConnectionDelegate>)delegate;

@property (nonatomic, weak) id<Lidar2DConnectionDelegate> delegate;

// I tell `device` to stop streaming distances and close the device.  I block until I am finished closing the device.
- (void)disconnect;

@property (nonatomic, readonly) NSString *serialNumber;
@property (nonatomic, readonly) NSUInteger rayCount;
@property (nonatomic, readonly) double coverageDegrees;

@end

@protocol Lidar2DConnectionDelegate <NSObject>

// I can send these on a private queue.  You must forward them to the main queue yourself.
- (void)connection:(Lidar2DConnection *)connection didFailWithError:(NSError *)error;
- (void)connection:(Lidar2DConnection *)connection didReceiveDistances:(Lidar2DDistance const *)distances;

@end

