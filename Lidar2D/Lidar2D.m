/*
 Created by Rob Mayoff on 12/8/12.
 Copyright (c) 2012 Rob Mayoff. All rights reserved.
 */

#import "ByteChannel.h"
#import "DqdObserverSet.h"
#import "Lidar2D.h"
#import "SCIP20Channel.h"
#import <termios.h>

typedef enum {
    ConnectionState_Disconnected,
    ConnectionState_Connecting, // Only while `q_connect` is executing.
    ConnectionState_Connected,
    ConnectionState_Disconnecting // Only while `q_disconnect` is executing.
} ConnectionState;

NSString *const Lidar2DErrorDomain = @"Lidar2DErrorDomain";
NSString *const Lidar2DErrorStatusKey = @"status";
NSString *const Lidar2DErrorExpectedStatusKey = @"expectedStatus";
static NSString *const SCIP20Status_OK = @"00";
static NSString *const SCIP20Status_StreamingData = @"99";

static int const kWriteTimeoutInMilliseconds = 1000;
static int const kReadTimeoutInMilliseconds = 1000;

// Hardcoded for URG-04LX.
static NSUInteger const kFirstRayStep = 44;
static NSUInteger const kLastRayStep = 725;
static double const kCoverageDegrees = 239.77;

@implementation Lidar2D {
    DqdObserverSet *observers_;
    dispatch_queue_t queue_;
    SCIP20Channel *channel_;
    int fd_;

    ConnectionState connectionState_;
    BOOL _isStreaming : 1;
}

#pragma mark - Public API

- (void)dealloc {
    [self stopStreamingWithoutRetainingMyself];
    [self disconnectWithoutRetainingMyself];
    dispatch_release(queue_);
}

- (id)initWithDevicePath:(NSString *)path {
    if ((self = [super init])) {
        _devicePath = [path copy];
        fd_ = -1;
        queue_ = dispatch_queue_create([[NSString stringWithFormat:@"com.dqd.MickeyMouseApp.Lidar2D-%@", path] UTF8String], 0);
        connectionState_ = ConnectionState_Disconnected;
    }
    return self;
}

@synthesize devicePath = _devicePath;

- (void)connect {
    dispatch_async(queue_, ^{ [self q_connect]; });
}

- (void)disconnect {
    [self stopStreaming];
    dispatch_async(queue_, ^{ [self q_disconnect]; });
}

- (BOOL)isConnected {
    return connectionState_ == ConnectionState_Connected;
}

@synthesize isStreaming = _isStreaming;

- (void)startStreaming {
    if (_isStreaming)
        return;
    abort(); // xxx
}

- (void)stopStreaming {
    if (!_isStreaming)
        return;
    abort(); // xxx
}

- (void)addObserver:(id<Lidar2DObserver>)observer {
    if (!observers_) {
        observers_ = [[DqdObserverSet alloc] initWithProtocol:@protocol(Lidar2DObserver)];
    }
    [observers_ addObserver:observer];
}

- (void)removeObserver:(id<Lidar2DObserver>)observer {
    [observers_ removeObserver:observer];
}

@synthesize serialNumber = _serialNumber;

- (NSUInteger)rayCount {
    return kLastRayStep - kFirstRayStep + 1;
}

- (double)coverageDegrees {
    return kCoverageDegrees;
}

#pragma mark - Implementation details

// Since I send myself this while in `dealloc`, I have to be careful not to retain myself, because retaining myself in `dealloc` will not prevent me from being deallocated!
- (void)stopStreamingWithoutRetainingMyself {
    abort(); // xxx
}

// Since I send myself this while in `dealloc`, I have to be careful not to retain myself, because retaining myself in `dealloc` will not prevent me from being deallocated!
- (void)disconnectWithoutRetainingMyself {
    abort(); // xxx
}

#pragma mark - Implementation details - background queue methods

- (void)q_setConnectionStateAndNotify:(ConnectionState)state {
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (state != connectionState_) {
            connectionState_ = state;
            switch (connectionState_) {
                case ConnectionState_Connected:
                    [observers_.proxy lidar2dDidConnect:self];
                    break;
                case ConnectionState_Disconnected:
                    [observers_.proxy lidar2dDidDisconnect:self];
                    break;
                case ConnectionState_Connecting:
                case ConnectionState_Disconnecting:
                    break;
            }
        }
    });
}

- (void)q_connect {
    // I only update connectionState_ synchronously so this is safe.
    if (connectionState_ == ConnectionState_Connected)
        return;
    [self q_setConnectionStateAndNotify:ConnectionState_Connecting];
    abort(); // xxx
    [self q_setConnectionStateAndNotify:ConnectionState_Connected];
}

- (void)q_disconnect {
    // I only update connectionState_ synchronously so this is safe.
    if (connectionState_ == ConnectionState_Disconnected)
        return;
    [self q_setConnectionStateAndNotify:ConnectionState_Disconnecting];
    abort(); // xxx
    [self q_setConnectionStateAndNotify:ConnectionState_Disconnected];
}

#pragma mark - Implementation details - streaming data

- (BOOL)startStreamingData {
    static NSString *command;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        command = [NSString stringWithFormat:@"MD%04lu%04lu00000", (unsigned long)kFirstRayStep, (unsigned long)kLastRayStep];
    });

    __block BOOL ok = YES;
    [channel_ sendCommand:command ignoringSpuriousResponses:NO onEmptyResponse:^(NSString *status) {
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
                block(data.bytes, &stop);
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
    && [self resetDevice]
    && [self initSCIP20Channel]
    && [self stopStreamingData]
    && [self setHighSensitivityMode]
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

- (BOOL)resetDevice {
    // I don't do this through the SCIP20Channel because I don't want SCIP20Channel to have to deal with starting up in the middle of a streaming data packet.
    static char const kResetCommands[] = "QT\nRS\n";
    static size_t kResetCommandsSize = sizeof kResetCommands - 1; // -1 for terminating NUL
    write(fd_, kResetCommands, kResetCommandsSize);
    char buffer[100];
    for (int i = 0; i < 2; ++i) {
        usleep(100000); // Allow some time for data to arrive.
        while (read(fd_, buffer, sizeof buffer) > 0) {
            // nothing
        }
    }
    return YES;
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
        _error = error;
        ok = NO;
    }];
    return ok;
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


