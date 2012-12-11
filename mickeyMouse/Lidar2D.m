/*
 Created by Rob Mayoff on 12/8/12.
 Copyright (c) 2012 Rob Mayoff. All rights reserved.
 */

#import "Lidar2D.h"
#import "Lidar2D_managerAccess.h"
#import "SCIP20Channel.h"
#import "ByteChannel.h"
#import <termios.h>

NSString *const Lidar2DErrorDomain = @"Lidar2DErrorDomain";
NSString *const Lidar2DErrorStatusKey = @"status";
NSString *const Lidar2DErrorExpectedStatusKey = @"expectedStatus";
static NSString *const SCIP20Status_OK = @"00";
static NSString *const SCIP20Status_StreamingData = @"99";

static int const kWriteTimeoutInMilliseconds = 1000;
static int const kReadTimeoutInMilliseconds = 1000;

@implementation Lidar2DDevice {
    NSString *path_;
    dispatch_queue_t queue_;
    SCIP20Channel *channel_;
    int fd_;
}

- (void)dealloc {
    dispatch_release(queue_);
}

#pragma mark - Public API - Lidar2DProxy

- (id)initWithDevicePath:(NSString *)path {
    if ((self = [super init])) {
        path_ = [path copy];
        fd_ = -1;
        queue_ = dispatch_queue_create([[NSString stringWithFormat:@"Lidar2D-%@", path] UTF8String], 0);
        [self performBlock:^(id<Lidar2D> device) {
            (void)device;
            [self connectToDevice];
        }];
    }
    return self;
}

- (void)performBlock:(void (^)(id<Lidar2D>))block {
    dispatch_async(queue_, ^{
        block(self);
    });
}

- (void)performBlockAndWait:(void (^)(id<Lidar2D>))block {
    dispatch_sync(queue_, ^{
        block(self);
    });
}

#pragma mark - Public API - Lidar2D

@synthesize devicePath = _devicePath;
@synthesize error = _error;
@synthesize serialNumber = _serialNumber;

- (void)forEachStreamingDataSnapshot:(Lidar2DDataSnapshotBlock)block {
    if ([self startStreamingData]) {
        [self readStreamingDataWithBlock:block];
        [self stopStreamingData];
    }
}

#pragma mark - Implementation details - streaming data

- (BOOL)startStreamingData {
    static NSString *const kCommand = @"MD0000076800000";
    __block BOOL ok = YES;
    [channel_ sendCommand:kCommand ignoringSpuriousResponses:NO onEmptyResponse:^(NSString *status) {
        ok = [self checkOKStatus:status];
    } onError:^(NSError *error) {
        _error = error;
        ok = NO;
    }];
    return ok;
}

- (void)readStreamingDataWithBlock:(Lidar2DDataSnapshotBlock)block {
    for (__block BOOL stop = NO; !stop; ) {
        [channel_ receiveStreamingResponseWithDataEncodingLength:3 onResponse:^(NSString *command, NSString *status, NSUInteger timestamp, NSData *data) {
            (void)command; (void)timestamp;

            if ([self checkStatus:status isEqualToStatus:SCIP20Status_StreamingData]) {
                block(data, &stop);
            } else {
                stop = YES;
            }
        } onError:^(NSError *error) {
            _error = error;
            stop = YES;
        }];
    }
}

- (BOOL)stopStreamingData {
    [channel_ sendCommand:@"QT" ignoringSpuriousResponses:YES onEmptyResponse:^(NSString *status) {
        [self checkOKStatus:status];
    } onError:^(NSError *error) {
        if (!_error) {
            _error = error;
        }
    }];
    return _error == nil;
}

- (BOOL)checkOKStatus:(NSString *)status {
    return [self checkStatus:status isEqualToStatus:SCIP20Status_OK];
}

- (BOOL)checkStatus:(NSString *)status isEqualToStatus:(NSString *)expectedStatus {
    if ([status isEqualToString:expectedStatus])
        return YES;
    if (!_error) {
        _error = [NSError errorWithDomain:Lidar2DErrorDomain code:0 userInfo:@{
            Lidar2DErrorStatusKey: status,
            Lidar2DErrorExpectedStatusKey: expectedStatus
        }];
    }
    return NO;
}

#pragma mark - Implementation details - error handling

// I return NO to make it easy to call me and then return NO.
- (BOOL)setPosixErrorWithAction:(NSString *)action {
    if (!_error) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{
            @"action": action,
            NSLocalizedDescriptionKey: @(strerror(errno)),
            NSFilePathErrorKey: path_
        }];
    }
    return NO;
}

- (BOOL)setErrorWithAction:(NSString *)action {
    if (!_error) {
        _error = [NSError errorWithDomain:Lidar2DErrorDomain code:0 userInfo:@{
            @"action": action,
            NSFilePathErrorKey: path_
        }];
    }
    return NO;
}

#pragma mark - Implementation details - connecting to device

- (void)connectToDevice {
    YES
    && [self openFile]
    && [self configureTerminalSettings]
    && [self initSCIP20Channel]
    && [self stopStreamingData]
    && [self readDeviceDictionaries];
}

- (BOOL)openFile {
    fd_ = open(path_.fileSystemRepresentation, O_RDWR | O_NONBLOCK | O_NOCTTY | O_EXLOCK);
    if (fd_ < 0) {
        return [self setPosixErrorWithAction:@"opening the device"];
    }

    if (fcntl(fd_, F_SETFD, fcntl(fd_, F_GETFD) | FD_CLOEXEC) < 0) {
        return [self setPosixErrorWithAction:@"setting the close-on-exec flag"];
    }

    return YES;
}

- (BOOL)configureTerminalSettings {
    struct termios tios = {
        .c_iflag = IGNBRK,
        .c_oflag = 0,
        .c_cflag = CS8 | CREAD | CLOCAL,
        .c_lflag = 0
    };
    memset(tios.c_cc, _POSIX_VDISABLE, NCCS);
    tios.c_cc[VMIN] = 1;
    tios.c_cc[VTIME] = 0;
    static const speed_t kSpeed = B115200;
    cfsetispeed(&tios, kSpeed);
    cfsetospeed(&tios, kSpeed);
    if (tcsetattr(fd_, TCSANOW, &tios) < 0) {
        return [self setPosixErrorWithAction:@"writing the device's terminal settings"];
    }

    return YES;
}

- (BOOL)initSCIP20Channel {
    ByteChannel *byteChannel = [[ByteChannel alloc] initWithFileDescriptor:fd_];
    channel_ = [[SCIP20Channel alloc] initWithByteChannel:byteChannel];
    return YES;
}

- (BOOL)readDeviceDictionaries {
    return YES
    && [self readVersionDictionary]
    && [self readSpecificationsDictionary]
    && [self readStateDictionary];
}

- (BOOL)readVersionDictionary {
    __block BOOL ok = YES;
    [channel_ sendCommand:@"VV" onDictionaryResponse:^(NSString *status, NSDictionary *info) {
        if (![self checkOKStatus:status])
            return;
        NSLog(@"device version: %@", info);
        _serialNumber = info[@"SERI"];
    } onError:^(NSError *error) {
        _error = error;
        ok = NO;
    }];
    return ok;
}

- (BOOL)readSpecificationsDictionary {
    __block BOOL ok = YES;
    [channel_ sendCommand:@"PP" onDictionaryResponse:^(NSString *status, NSDictionary *info) {
        if (![self checkOKStatus:status])
            return;
        NSLog(@"device specifications: %@", info);
    } onError:^(NSError *error) {
        _error = error;
        ok = NO;
    }];
    return ok;
}

- (BOOL)readStateDictionary {
    __block BOOL ok = YES;
    [channel_ sendCommand:@"II" onDictionaryResponse:^(NSString *status, NSDictionary *info) {
        if (![self checkOKStatus:status])
            return;
        NSLog(@"device state: %@", info);
    } onError:^(NSError *error) {
        _error = error;
        ok = NO;
    }];
    return ok;
}

@end


