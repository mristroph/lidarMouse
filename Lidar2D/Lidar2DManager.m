/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import "Lidar2D+Creation.h"
#import "Lidar2DManager.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <mach/mach.h>

@interface Lidar2DManager ()
@end

@implementation Lidar2DManager {
    IONotificationPortRef notificationPort_;
    CFRunLoopRef runLoop_;
}

static void firstMatchCallback(__unsafe_unretained Lidar2DManager *refcon, io_iterator_t iterator);

#pragma mark - Public API

@synthesize delegate = _delegate;

- (void)start {
    if (self.isStarted)
        return;

    if (!_delegate) {
        [NSException raise:NSInternalInconsistencyException format:@"No delegate set for %@", self];
        abort();
    }

    notificationPort_ = IONotificationPortCreate(kIOMasterPortDefault);
    if (!notificationPort_) {
        [self failWithAction:@"Creating I/O notification port"];
    }

    runLoop_ = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop_, IONotificationPortGetRunLoopSource(notificationPort_), kCFRunLoopDefaultMode);

    NSMutableDictionary *filter = [self ioServiceMatchingFilter];
    io_iterator_t iterator;
    kern_return_t rc = IOServiceAddMatchingNotification(notificationPort_, kIOFirstMatchNotification, CFBridgingRetain(filter), (IOServiceMatchingCallback)firstMatchCallback, (__bridge void *)self, &iterator);
    if (rc != KERN_SUCCESS) {
        [self failWithAction:@"Registering for device match notifications" kernelReturnCode:rc];
        return;
    }
    firstMatchCallback(self, iterator);
}

- (void)stop {
    if (!self.isStarted)
        return;

    if (notificationPort_) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notificationPort_), kCFRunLoopDefaultMode);
        IONotificationPortDestroy(notificationPort_);
    }
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Implementation details

- (BOOL)isStarted {
    return runLoop_ != NULL;
}

- (void)failWithAction:(NSString *)action kernelReturnCode:(kern_return_t)kernelReturnCode {
    NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:kernelReturnCode userInfo:@{
        @"action": action,
        NSLocalizedDescriptionKey: @(mach_error_string(kernelReturnCode))
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate lidar2DManager:self didReceiveError:error];
    });
}

- (void)failWithAction:(NSString *)action {
    NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:0 userInfo:@{ @"action": action }];
    [_delegate lidar2DManager:self didReceiveError:error];
}

- (void)observeFirstMatchNotificationWithService:(io_service_t)service {
    if (!self.isStarted)
        return;

    Lidar2D *device = [[Lidar2D alloc] initWithIOService:service];
    [_delegate lidar2DManager:self didConnectToDevice:device];
}

- (NSMutableDictionary *)ioServiceMatchingFilter {
    NSMutableDictionary *filter = CFBridgingRelease(IOServiceMatching(kIOUSBDeviceClassName));
    filter[@kUSBVendorID] = @0x15d1;
    filter[@kUSBProductID] = @0x0;
    return filter;
}

static void firstMatchCallback(__unsafe_unretained Lidar2DManager *unsafe_self, io_iterator_t iterator) {
    Lidar2DManager *self = unsafe_self;
    io_object_t service;
    while ((service = IOIteratorNext(iterator))) {
        [self observeFirstMatchNotificationWithService:service];
        IOObjectRelease(service);
    }
}

@end
