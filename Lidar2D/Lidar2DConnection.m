//
//  Lidar2DConnection.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/14/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "Lidar2DConnection.h"
#import "SCIP20Channel.h"
#import "ByteChannel.h"
#import <termios.h>

// Hardcoded for URG-04LX.
static NSUInteger const kFirstRayStep = 44;
static NSUInteger const kLastRayStep = 725;
static double const kCoverageDegrees = 239.77;

NSString *const Lidar2DErrorDomain = @"Lidar2DErrorDomain";
NSString *const Lidar2DErrorStatusKey = @"status";
NSString *const Lidar2DErrorExpectedStatusKey = @"expectedStatus";
static NSString *const SCIP20Status_OK = @"00";
static NSString *const SCIP20Status_StreamingData = @"99";

static int const kWriteTimeoutInMilliseconds = 1000;
static int const kReadTimeoutInMilliseconds = 1000;

@implementation Lidar2DConnection {
    dispatch_queue_t queue_;  // I run my streaming data reader loop on this queue.
    __weak id<Lidar2DConnectionDelegate> delegate_;
    NSString *devicePath_;
    SCIP20Channel *channel_;
    int fd_;
    volatile BOOL wantStreaming_ : 1;
}

#pragma mark - Package API

- (id)initWithDevicePath:(NSString *)devicePath delegate:(id<Lidar2DConnectionDelegate>)delegate {
    if (self = [super init]) {
        devicePath_ = [devicePath copy];
        delegate_ = delegate;
        queue_ = dispatch_queue_create([[NSString stringWithFormat:@"com.dqd.Lidar2DConnection-%s", devicePath.fileSystemRepresentation] UTF8String], 0);
        wantStreaming_ = YES;
        if (![self connect])
            return nil;
        dispatch_async(queue_, ^{
            [self q_receiveStreamingData];
        });
    }
    return self;
}

- (void)disconnect {
    wantStreaming_ = NO;
    // Wait for the background loop to stop.
    dispatch_sync(queue_, ^{});
    [self stopStreamingData];
    channel_ = nil;
    close(fd_);
    fd_ = -1;
}

@synthesize serialNumber = _serialNumber;

- (NSUInteger)rayCount {
    return kLastRayStep - kFirstRayStep + 1;
}

- (double)coverageDegrees {
    return kCoverageDegrees;
}

#pragma mark - Connection details

- (BOOL)connect {
    return YES
    && [self openFile]
    && [self configureTerminalSettings]
    && [self resetDevice]
    && [self initSCIP20Channel]
    && [self setHighSensitivityMode]
    && [self readDeviceDictionaries]
    && [self startStreaming];
}

- (BOOL)openFile {
    fd_ = open(devicePath_.fileSystemRepresentation, O_RDWR | O_NONBLOCK | O_NOCTTY | O_EXLOCK);
    if (fd_ < 0) {
        return [self reportPosixErrorWithAction:@"opening the device"];
    }

    if (fcntl(fd_, F_SETFD, fcntl(fd_, F_GETFD) | FD_CLOEXEC) < 0) {
        return [self reportPosixErrorWithAction:@"setting the close-on-exec flag"];
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
        return [self reportPosixErrorWithAction:@"writing the device's terminal settings"];
    }

    return YES;
}

- (BOOL)resetDevice {
    // I don't do this through the SCIP20Channel because I don't want SCIP20Channel to have to deal with starting up in the middle of a streaming data packet.
    [self writeCommandAndFlushIncomingBytes:"QT\n"];
    [self writeCommandAndFlushIncomingBytes:"RS\n"];
    return YES;
}

- (void)writeCommandAndFlushIncomingBytes:(char const *)command {
    write(fd_, command, strlen(command));
    static char buffer[4096]; // I don't need what I read so it doesn't matter if it's clobbered.
    for (int i = 0; i < 4; ++i) {
        usleep(100000); // Allow some time for data to arrive.
        while (read(fd_, buffer, sizeof buffer) > 0) {
            // nothing
        }
    }
}

- (BOOL)initSCIP20Channel {
    ByteChannel *byteChannel = [[ByteChannel alloc] initWithFileDescriptor:fd_];
    channel_ = [[SCIP20Channel alloc] initWithByteChannel:byteChannel];
    return YES;
}

- (BOOL)setHighSensitivityMode {
    __block BOOL ok;
    [channel_ sendCommand:@"HS1" ignoringSpuriousResponses:NO onEmptyResponse:^(NSString *status) {
        ok = [self checkOKStatus:status];
    } onError:^(NSError *error) {
        [delegate_ connection:self didFailWithError:error];
        ok = NO;
    }];
    return ok;
}

- (BOOL)startStreaming {
    wantStreaming_ = YES;
        NSString *command = [NSString stringWithFormat:@"MD%04lu%04lu00000", (unsigned long)kFirstRayStep, (unsigned long)kLastRayStep];
    __block BOOL didSucceed = NO;
    __block BOOL shouldKeepLooping = YES;
    BOOL isFirstTime = YES;
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent() + 20;
    do {
        if (isFirstTime) {
            isFirstTime = NO;
        } else {
            usleep(250000);
        }
        
        [channel_ sendCommand:command ignoringSpuriousResponses:NO onEmptyResponse:^(NSString *status) {
            if ([status isEqualToString:@"0J"]) {
                // Undocumented status code that appears for about 10 seconds when the device is connected.  I assume it means "not ready, try again soon".
            } else {
                shouldKeepLooping = NO;
                didSucceed = [self checkOKStatus:status];
            }
        } onError:^(NSError *error) {
            [delegate_ connection:self didFailWithError:error];
            shouldKeepLooping = NO;
            didSucceed = NO;
        }];
    } while (shouldKeepLooping && CFAbsoluteTimeGetCurrent() < endTime);
    return didSucceed;
}

#pragma mark - Disconnection details

- (void)stopStreamingData {
    [channel_ sendCommand:@"QT" ignoringSpuriousResponses:YES onEmptyResponse:^(NSString *status) {
        [self checkOKStatus:status];
    } onError:^(NSError *error) {
        [delegate_ connection:self didFailWithError:error];
    }];
}

#pragma mark - Streaming data receiver details

- (void)q_receiveStreamingData {
    while (wantStreaming_) {
        [channel_ receiveStreamingResponseWithDataEncodingLength:3 onResponse:^(NSString *command, NSString *status, NSUInteger timestamp, NSData *data) {
            (void)command; (void)timestamp;
            if ([self checkStatus:status isEqualToStatus:SCIP20Status_StreamingData]) {
                [delegate_ connection:self didReceiveDistances:data.bytes];
            } else {
                wantStreaming_ = NO;
            }
        } onError:^(NSError *error) {
            [delegate_ connection:self didFailWithError:error];
            wantStreaming_ = NO;
        }];
    }
}

#pragma mark - Error reporting details

// I return NO to make it easy to call me and then return NO.
- (BOOL)reportPosixErrorWithAction:(NSString *)action {
    [delegate_ connection:self didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{
        @"action": action,
        NSLocalizedDescriptionKey: @(strerror(errno)),
        NSFilePathErrorKey: devicePath_
    }]];
    return NO;
}

#pragma mark - Device dictionary details

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
        [delegate_ connection:self didFailWithError:error];
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
        [delegate_ connection:self didFailWithError:error];
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
        [delegate_ connection:self didFailWithError:error];
        ok = NO;
    }];
    return ok;
}

#pragma mark - Status checking details

- (BOOL)checkOKStatus:(NSString *)status {
    return [self checkStatus:status isEqualToStatus:SCIP20Status_OK];
}

- (BOOL)checkStatus:(NSString *)status isEqualToStatus:(NSString *)expectedStatus {
    if ([status isEqualToString:expectedStatus])
        return YES;
    [delegate_ connection:self didFailWithError:[NSError errorWithDomain:Lidar2DErrorDomain code:0 userInfo:@{
        Lidar2DErrorStatusKey: status,
        Lidar2DErrorExpectedStatusKey: expectedStatus
    }]];
    return NO;
}

@end
