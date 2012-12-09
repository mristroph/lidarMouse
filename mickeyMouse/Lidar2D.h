/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import <Foundation/Foundation.h>

@protocol Lidar2D <NSObject>

@property (nonatomic, readonly) NSString *devicePath;

// This is an error I have encountered, or nil.  Set this to nil after handling the error if you want to keep using me and detect more errors.  You need to check this immediately after creation.  If it is non-nil, don't try to use me for anything else.
@property (nonatomic, strong) NSError *error;

@property (nonatomic, readonly) NSString *serialNumber;

@end

@protocol Lidar2DProxy <NSObject>

// Execute `block` asynchronously on this device's private serial queue.
- (void)performBlock:(void (^)(id<Lidar2D> device))block;

// Execute `block` synchronously on this device's private serial queue.
- (void)performBlockAndWait:(void (^)(id<Lidar2D> device))block;

@end
