/*
 Created by Rob Mayoff on 12/8/12.
 Copyright (c) 2012 Rob Mayoff. All rights reserved.
 */

#import "Lidar2D.h"
#import "Lidar2D_managerAccess.h"
#import <termios.h>
#import <poll.h>

static NSString *const Lidar2DErrorDomain = @"Lidar2DErrorDomain";

static int const kWriteTimeoutInMilliseconds = 1000;
static int const kReadTimeoutInMilliseconds = 1000;

// Spend up to `timeout` milliseconds trying to write the buffer to the file descriptor.  You must set the file to non-blocking mode before calling me.  I always return the number of bytes written.  If I return a number less than `length`, check `errno`.  I set `errno` to `EAGAIN` if the time expires.
static size_t writeWithTimeoutInMilliseconds(int fd, char const *buffer, size_t length, int timeout);

// Spend up to `timeout` milliseconds trying to read from the file descriptor.  You must set the file to non-blocking mode before calling me.   I always return the number of bytes read.  As soon as I read any bytes, I return.  I don't wait for more bytes after I've put some in the buffer.  On EOF, I set `errno` to zero and return zero.  On timeout, I set `errno` to `EAGAIN` and return zero.  On any other error, I leave the system error code in `errno` and return zero.
static size_t readWithTimeoutInMilliseconds(int fd, char *buffer, size_t capacity, int timeout);

@implementation Lidar2DDevice {
    NSString *path_;
    dispatch_queue_t queue_;
    int fd_;
    NSInputStream *inputStream_;
    uint64_t commandNumber_;

    char inputBuffer_[8192];
    ssize_t inputBufferReadOffset_;
    ssize_t inputBufferWriteOffset_;
}

- (void)dealloc {
    if (fd_ != -1) {
        close(fd_);
    }
    dispatch_release(queue_);
}

#pragma mark - Public API - Lidar2DProxy

- (id)initWithDevicePath:(NSString *)path {
    if ((self = [super init])) {
        path_ = [path copy];
        fd_ = -1;
        queue_ = dispatch_queue_create([[NSString stringWithFormat:@"Lidar2D-%@", path] UTF8String], 0);
        [self performBlock:^(id<Lidar2D> device) {
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

#pragma mark - Implementation details

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

- (void)connectToDevice {
    YES
    && [self openFile]
    && [self configureTerminalSettings]
    && [self sendVVAndReadResponse];
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

- (BOOL)sendVVAndReadResponse {
    if (![self sendCommandAndReceiveEcho:"VV"]
        || ![self receiveAndCheckStatus:"00P"])
        return NO;
    while (true) {
        NSData *data = [self readLine];
        if (!data)
            return NO;
        if (data.length == 0)
            return YES;
        NSLog(@"line=%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    }
}

- (BOOL)sendCommandAndReceiveEcho:(char const *)command {
    char buffer[100];
    size_t bytesToWrite = [self lengthOfBuffer:buffer capacity:sizeof buffer byFormattingCommand:command];
    return [self sendBytes:buffer length:bytesToWrite]
        && [self readAndMatchBytes:buffer length:bytesToWrite];
}

- (size_t)lengthOfBuffer:(char *)buffer capacity:(size_t)capacity byFormattingCommand:(char const *)command {
    ++commandNumber_;
    int length = snprintf(buffer, capacity, "%s;%016llu\n", command, commandNumber_);
    if (length >= capacity) {
        [NSException raise:NSInvalidArgumentException format:@"command too long for buffer: %s", command];
        abort();
    }
    return length;
}

- (BOOL)sendBytes:(char const *)buffer length:(size_t)length {
    ssize_t rc = writeWithTimeoutInMilliseconds(fd_, buffer, length, kWriteTimeoutInMilliseconds);
    return rc == length ? YES : [self setPosixErrorWithAction:@"sending command"];
}

- (BOOL)readAndMatchBytes:(char const *)buffer length:(size_t)length {
    for (size_t i = 0; i < length; ++i) {
        if (![self readAndMatchByte:buffer[i]]) {
            [self setErrorWithAction:@"command echo is incorrect"];
        }
    }
    return YES;
}

- (BOOL)readAndMatchByte:(char)expectedByte {
    char actualByte;
    if (![self readByte:&actualByte])
        return NO;
    return expectedByte == actualByte ? YES : [self setErrorWithAction:@"matching input"];
}

- (BOOL)receiveAndCheckStatus:(char const *)status {
    for (char const *p = status; *p; ++p) {
        if (![self readAndMatchByte:*p])
            return NO;
    }
    return [self readAndMatchByte:'\n'];
}

- (BOOL)readByte:(char *)byteOut {
    if (inputBufferReadOffset_ >= inputBufferWriteOffset_) {
        if (![self fillInputBuffer])
            return NO;
    }
    *byteOut = inputBuffer_[inputBufferReadOffset_++];
    return YES;
}

- (NSData *)readLine {
    NSMutableData *data = [[NSMutableData alloc] init];
    while (true) {
        char byte;
        if (![self readByte:&byte])
            return NO;
        if (byte == '\n')
            return data;
        [data appendBytes:&byte length:1];
    }
}

- (BOOL)fillInputBuffer {
    if (inputBufferReadOffset_ > 0 && inputBufferWriteOffset_ > inputBufferReadOffset_) {
        memmove(inputBuffer_, inputBuffer_ + inputBufferReadOffset_, inputBufferWriteOffset_ - inputBufferReadOffset_);
        inputBufferWriteOffset_ -= inputBufferReadOffset_;
        inputBufferReadOffset_ = 0;
    }
    ssize_t rc = readWithTimeoutInMilliseconds(fd_, inputBuffer_ + inputBufferWriteOffset_, (sizeof inputBuffer_) - inputBufferWriteOffset_, kReadTimeoutInMilliseconds);
    if (rc == 0) {
        return [self setPosixErrorWithAction:@"reading from the device"];
    }
    inputBufferWriteOffset_ += rc;
    return YES;
}

@end

static size_t writeWithTimeoutInMilliseconds(int fd, char const *buffer, size_t length, int timeout) {
    struct pollfd pfd = { .fd = fd, .events = POLLOUT };
    size_t offset = 0;
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent() + timeout / 1000.0;
    while (offset < length) {
        ssize_t rc = poll(&pfd, 1, timeout);
        if (rc < 0)
            break;
        if (rc == 0) {
            errno = EAGAIN;
            break;
        }

        rc = write(fd, buffer + offset, length - offset);
        if (rc < 1)
            break;

        offset += rc;
        CFTimeInterval timeRemaining = endTime - CFAbsoluteTimeGetCurrent();
        timeout = (int)ceil(timeRemaining * 1000);
    }

    return offset;
}

static size_t readWithTimeoutInMilliseconds(int fd, char *buffer, size_t capacity, int timeout) {
    struct pollfd pfd = { .fd = fd, .events = POLLIN };
    ssize_t rc = poll(&pfd, 1, timeout);
    if (rc < 0)
        return 0;
    if (rc == 0) {
        errno = EAGAIN;
        return 0;
    }

    rc = read(fd, buffer, capacity);
    if (rc < 0)
        return 0;
    if (rc == 0) {
        errno = 0;
        return 0;
    }
    return rc;
}


