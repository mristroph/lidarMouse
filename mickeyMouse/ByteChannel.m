/*
Created by Rob Mayoff on 12/9/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import "ByteChannel.h"
#import <poll.h>

static size_t writeWithDeadline(int fd, char const *buffer, size_t length, CFAbsoluteTime timeout);
static size_t readWithDeadline(int fd, char *buffer, size_t capacity, CFAbsoluteTime timeout);

@implementation ByteChannel {
    NSUInteger readOffset_;
    NSUInteger writeOffset_;
    int fd_;
    char buffer_[8192];
}

#pragma mark - Public API

@synthesize error = _error;

- (id)initWithFileDescriptor:(int)fd {
    if ((self = [super init])) {
        fd_ = fd;
        readOffset_ = 0;
        writeOffset_ = 0;
    }
    return self;
}

- (BOOL)sendData:(NSData *)data withTimeout:(CFTimeInterval)timeout {
    NSLog(@"sendData:%@", data);
    size_t bytesWritten = writeWithDeadline(fd_, data.bytes, data.length, CFAbsoluteTimeGetCurrent() + timeout);
    if (bytesWritten == data.length)
        return YES;
    _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return NO;
}

- (NSData *)readDataUntilTerminator:(char)terminator includingTerminator:(BOOL)includingTerminator withDeadline:(CFAbsoluteTime)deadline {
    NSMutableData *data = [NSMutableData data];
    __block BOOL shouldKeepReading;
    do {
        [self readAndConsumeDataIncludingTerminator:terminator withDeadline:deadline onTerminatorFound:^(char const *begin, char const *end) {
            shouldKeepReading = NO;
            if (!includingTerminator) {
                --end;
            }
            [data appendBytes:begin length:end - begin];
        } onTerminatorMissing:^(char const *begin, char const *end) {
            shouldKeepReading = YES;
            [data appendBytes:begin length:end - begin];
        } onError:^{
            shouldKeepReading = NO;
            _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }];
    } while (shouldKeepReading);
    return data;
}

#pragma mark - Implementation details

- (void)readAndConsumeDataIncludingTerminator:(char)terminator withDeadline:(CFAbsoluteTime)deadline onTerminatorFound:(void (^)(char const *begin, char const *end))terminatorFoundBlock onTerminatorMissing:(void (^)(char const *begin, char const *end))terminatorMissingBlock onError:(void (^)(void))errorBlock {
    if (readOffset_ >= writeOffset_ && ![self readIntoBufferWithDeadline:deadline]) {
        errorBlock();
        return;
    }

    char const *begin = buffer_ + readOffset_;
    char const *end = memchr(begin, terminator, writeOffset_ - readOffset_);
    if (end) {
        ++end;
        terminatorFoundBlock(begin, end);
    } else {
        end = buffer_ + writeOffset_;
        terminatorMissingBlock(begin, end);
    }
    readOffset_ += end - begin;
}

- (BOOL)readIntoBufferWithDeadline:(CFAbsoluteTime)deadline {
    memmove(buffer_, buffer_ + readOffset_, writeOffset_ - readOffset_);
    writeOffset_ -= readOffset_;
    readOffset_ = 0;

    size_t bytesRead = readWithDeadline(fd_, buffer_ + writeOffset_, (sizeof buffer_) - writeOffset_, deadline);
    writeOffset_ += bytesRead;
    return bytesRead > 0;
}

@end

static int millisecondsUntilDeadline(CFAbsoluteTime deadline) {
    return MAX(0, (int)ceil((deadline - CFAbsoluteTimeGetCurrent()) * 1000));
}

static size_t writeWithDeadline(int fd, char const *buffer, size_t length, CFAbsoluteTime deadline) {
    struct pollfd pfd = { .fd = fd, .events = POLLOUT };
    size_t offset = 0;
    while (offset < length) {
        ssize_t rc = poll(&pfd, 1, millisecondsUntilDeadline(deadline));
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
    }

    return offset;
}

static size_t readWithDeadline(int fd, char *buffer, size_t capacity, CFAbsoluteTime deadline) {
    struct pollfd pfd = { .fd = fd, .events = POLLIN };
    ssize_t rc = poll(&pfd, 1, millisecondsUntilDeadline(deadline));
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
