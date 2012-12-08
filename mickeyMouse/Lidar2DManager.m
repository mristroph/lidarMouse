/*
Created by Rob Mayoff on 12/8/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import "Lidar2DManager.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <mach/mach.h>

@implementation Lidar2DManager {
    IONotificationPortRef notificationPort_;
    BOOL isScheduled_ : 1;
}

static void firstMatchCallback(void *refcon, io_iterator_t iterator);

#pragma mark - Public API

- (void)start {
    if (isScheduled_)
        return;

    if (!_delegate) {
        [NSException raise:NSInternalInconsistencyException format:@"No delegate set for %@", self];
        abort();
    }

    notificationPort_ = IONotificationPortCreate(kIOMasterPortDefault);
    if (!notificationPort_) {
        [self failWithAction:@"Creating I/O notification port"];
    }

    NSMutableDictionary *filter = [self ioServiceMatchingFilter];
    io_iterator_t iterator;
    kern_return_t rc = IOServiceAddMatchingNotification(notificationPort_, kIOFirstMatchNotification, CFBridgingRetain(filter), firstMatchCallback, (__bridge void *)self, &iterator);
    if (rc != KERN_SUCCESS) {
        [self failWithAction:@"Registering for device match notifications" kernelReturnCode:rc];
        return;
    }
    [self didMatchDevicesWithIterator:iterator];
}

- (void)stop {
    if (!isScheduled_)
        return;

    if (notificationPort_) {
        IONotificationPortDestroy(notificationPort_);
    }
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Implementation details

- (void)failWithAction:(NSString *)action kernelReturnCode:(kern_return_t)kernelReturnCode {
    NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:kernelReturnCode userInfo:@{
        NSLocalizedDescriptionKey: @(mach_error_string(kernelReturnCode))
    }];
    [_delegate lidar2DManager:self didReceiveError:error];
}

- (void)failWithAction:(NSString *)action {
    NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:0 userInfo:nil];
    [_delegate lidar2DManager:self didReceiveError:error];
}

- (NSMutableDictionary *)ioServiceMatchingFilter {
    NSMutableDictionary *filter = (__bridge NSMutableDictionary *)(IOServiceMatching(kIOUSBDeviceClassName));
    filter[@kUSBVendorID] = @0x15d1;
    filter[@kUSBProductID] = @0x0;
    return filter;
}

- (void)didMatchDevicesWithIterator:(io_iterator_t)iterator {
    io_object_t device;
    while ((device = IOIteratorNext(iterator))) {
        [self dumpObject:device];
        IOObjectRelease(device);
    }
}

- (void)dumpObject:(io_object_t)object {
    NSString *className = CFBridgingRelease(IOObjectCopyClass(object));
    NSLog(@"%u class = %@", object, className);
    NSString *property = CFBridgingRelease(IORegistryEntryCreateCFProperty(object, CFSTR(kUSBDevicePropertyLocationID), NULL, 0));
    NSLog(@"%u locationID = %x", object, property.intValue);
}

static void firstMatchCallback(void *refcon, io_iterator_t iterator) {
    [(__bridge Lidar2DManager *)refcon didMatchDevicesWithIterator:iterator];
}

@end
