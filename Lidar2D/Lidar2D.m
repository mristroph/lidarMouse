/*
 Created by Rob Mayoff on 12/8/12.
 Copyright (c) 2012 Rob Mayoff. All rights reserved.
 */

#import "DqdObserverSet.h"
#import "Lidar2D.h"
#import "Lidar2DConnection.h"
#import "Lidar2D+Creation.h"
#import <IOKit/serial/IOSerialKeys.h>
#import <mach/mach_error.h>

#define kRunLoopForIONotificationPort (CFRunLoopGetMain())
#define kRunLoopModeForIONotificationPort (kCFRunLoopDefaultMode)

static NSString *dialinDevicePathForIOService(io_service_t service) {
    NSString *path = CFBridgingRelease(IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR(kIODialinDeviceKey), NULL, kIORegistryIterateRecursively));
    return path;
}


@interface Lidar2D () <Lidar2DConnectionDelegate>
@end

@implementation Lidar2D {
    IONotificationPortRef ioNotificationPort_;
    DqdObserverSet *observers_;
    dispatch_queue_t queue_; // I use this to sequence changes to connection_.connectionState.  Blocks on this queue don't return until they have finished making the state changes.
    dispatch_group_t group_; // I queue all tasks in this group so I can easily tell when I have pending tasks.  However, I don't use dispatch_group_async because each task needs to leave the group before sending any notifications to my observers, so isBusy will return the correct value.
    Lidar2DConnection *connection_;
    BOOL didTerminate_ : 1;
}

#pragma mark - Public API

- (void)dealloc {
    if (connection_) {
        Lidar2DConnection *connection = connection_; // prevent block from retaining me
        connection.delegate = nil;

        // Don't need to enter the group here because it's too late for anyone to ask me isBusy.
        dispatch_async(queue_, ^{
            [connection disconnect];
        });
    }

    if (group_) {
        dispatch_release(group_);
    }

    if (queue_) {
        dispatch_release(queue_);
    }

    if (ioNotificationPort_) {
        CFRunLoopRemoveSource(kRunLoopForIONotificationPort, IONotificationPortGetRunLoopSource(ioNotificationPort_), kRunLoopModeForIONotificationPort);
        IONotificationPortDestroy(ioNotificationPort_);
    }
}

- (id)initWithIOService:(io_service_t)service {
    if ((self = [super init])) {
        if (![self startObservingTerminationNotificationsForIOService:service])
            return nil;
        _devicePath = dialinDevicePathForIOService(service);
        queue_ = dispatch_queue_create([[NSString stringWithFormat:@"com.dqd.Lidar2D-%s", _devicePath.fileSystemRepresentation] UTF8String], 0);
        group_ = dispatch_group_create();
        observers_ = [[DqdObserverSet alloc] initWithProtocol:@protocol(Lidar2DObserver)];
    }
    return self;
}

@synthesize devicePath = _devicePath;

- (void)connect {
    dispatch_group_enter(group_);
    dispatch_async(queue_, ^{
        if (connection_)
            return;
        connection_ = [[Lidar2DConnection alloc] initWithDevicePath:_devicePath delegate:self];
        dispatch_group_leave(group_);
        if (connection_) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [observers_.proxy lidar2dDidConnect:self];
            });
        }
    });
}

- (void)disconnect {
    dispatch_group_enter(group_);
    dispatch_async(queue_, ^{
        if (!connection_)
            return;
        [connection_ disconnect];
        connection_ = nil;
        dispatch_group_leave(group_);
        dispatch_sync(dispatch_get_main_queue(), ^{
            [observers_.proxy lidar2dDidDisconnect:self];
        });
    });
}

- (BOOL)isBusy {
    return dispatch_group_wait(group_, DISPATCH_TIME_NOW) != 0;
}

- (BOOL)isConnected {
    return connection_ != nil;
}

- (void)addObserver:(id<Lidar2DObserver>)observer {
    [observers_ addObserver:observer];
}

- (void)removeObserver:(id<Lidar2DObserver>)observer {
    [observers_ removeObserver:observer];
}

- (NSString *)serialNumber {
    return connection_.serialNumber;
}

- (NSUInteger)rayCount {
    return connection_.rayCount;
}

- (double)coverageDegrees {
    return connection_.coverageDegrees;
}

- (double)firstRayOffsetDegrees {
    return connection_.firstRayOffsetDegrees;
}

#pragma mark - Lidar2DConnectionDelegate protocol

- (void)connection:(Lidar2DConnection *)connection didFailWithError:(NSError *)error {
    (void)connection;
    dispatch_async(dispatch_get_main_queue(), ^{
        [observers_.proxy lidar2d:self didFailWithError:error];
    });
}

- (void)connection:(Lidar2DConnection *)connection didReceiveDistances:(const Lidar2DDistance *)distances {
    (void)connection;
    NSData *data = [[NSData alloc] initWithBytes:distances length:connection.rayCount * sizeof *distances];
    dispatch_async(dispatch_get_main_queue(), ^{
        [observers_.proxy lidar2d:self didReceiveDistances:data.bytes];
    });
}

#pragma mark - Implementation details

- (void)observeTerminationNotificationsWithIOIterator:(io_iterator_t)iterator {
    io_service_t service;
    BOOL didFindService = NO;
    while ((service = IOIteratorNext(iterator))) {
        didFindService = YES;
        IOObjectRelease(service);
    }
    if (didFindService && !didTerminate_) {
        didTerminate_ = YES;
        [observers_.proxy lidar2DDidTerminate:self];
    }
}

static void observeTerminationNotifications(void *refCon, io_iterator_t iterator) {
    Lidar2D *self = (__bridge id)refCon;
    [self observeTerminationNotificationsWithIOIterator:iterator];
}

- (BOOL)startObservingTerminationNotificationsForIOService:(io_service_t)service {
    uint64_t entryID;
    kern_return_t rc = IORegistryEntryGetRegistryEntryID(service, &entryID);
    if (rc != KERN_SUCCESS) {
        NSLog(@"error: IORegistryEntryGetRegistryEntryID returned %d (%s)", rc, mach_error_string(rc));
        return NO;
    }

    ioNotificationPort_ = IONotificationPortCreate(kIOMasterPortDefault);
    if (!ioNotificationPort_) {
        NSLog(@"error: IONotificationPortCreate failed");
        return NO;
    }

    CFRunLoopAddSource(kRunLoopForIONotificationPort, IONotificationPortGetRunLoopSource(ioNotificationPort_), kRunLoopModeForIONotificationPort);

    CFMutableDictionaryRef filter = IORegistryEntryIDMatching(entryID);
    io_iterator_t iterator;
    rc = IOServiceAddMatchingNotification(ioNotificationPort_, kIOTerminatedNotification, filter, observeTerminationNotifications, (__bridge void *)self, &iterator);
    if (rc != KERN_SUCCESS) {
        NSLog(@"error: IOServiceAddMatchingNotification failed: %d (%s)", rc, mach_error_string(rc));
    }
    // Note: IOServiceAddMatchingNotification released filter.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self observeTerminationNotificationsWithIOIterator:iterator];
    });
    return YES;
}

@end


