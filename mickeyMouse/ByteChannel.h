/*
Created by Rob Mayoff on 12/9/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import <Foundation/Foundation.h>

@interface ByteChannel : NSObject

// I assume `fd` is set to non-blocking.  If it's not, I won't honor deadlines.
- (id)initWithFileDescriptor:(int)fd;

@property (nonatomic, strong) NSError *error;

- (BOOL)sendData:(NSData *)data withTimeout:(CFTimeInterval)timeout;

- (NSData *)readDataUntilTerminator:(char)terminator includingTerminator:(BOOL)includingTerminator withDeadline:(CFAbsoluteTime)deadline;

@end
