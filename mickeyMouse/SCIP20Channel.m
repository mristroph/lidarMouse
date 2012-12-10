/*
Created by Rob Mayoff on 12/9/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import "SCIP20Channel.h"
#import "ByteChannel.h"

NSString *const SCIP20ErrorDomain = @"SCIP 2.0 Error Domain";

// A `SCIP20ResponsePacketBlock` receives the pieces of a response.  The `status` is the status field with the checksum and newline removed.  Each `payloadChunk` is one line of the data section with the checksum and newline removed, as an `NSData`.
typedef void (^SCIP20ResponsePacketBlock)(NSString *status, NSArray *payloadChunks);

static NSString *commandFromEchoLine(NSData *echoLine) {
    NSMutableString *command = [[NSMutableString alloc] initWithData:echoLine encoding:NSUTF8StringEncoding];
    NSRange range = [command rangeOfString:@";" options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        // just the newline
        range = NSMakeRange(command.length - 1, 1);
    } else {
        range.length = command.length - range.location;
    }
    [command deleteCharactersInRange:range];
    return command;
}

@implementation SCIP20Channel {
    ByteChannel *channel_;
    uint64_t commandNumber_;
    CFAbsoluteTime deadline_;
}

#pragma mark - Public API

@synthesize timeout = _timeout;

- (id)initWithByteChannel:(ByteChannel *)byteChannel {
    if (self = [super init]) {
        channel_ = byteChannel;
        _timeout = 1;
    }
    return self;
}

- (void)sendCommand:(NSString *)command ignoringSpuriousResponses:(BOOL)ignoringSpuriousResponses onEmptyResponse:(SCIP20EmptyResponseBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock {
    [self sendCommand:command ignoringSpuriousResponses:ignoringSpuriousResponses onResponse:^(NSString *status, NSArray *payloadChunks) {
        if (payloadChunks.count > 0) {
            errorBlock([NSError errorWithDomain:SCIP20ErrorDomain code:SCIP20ErrorCode_UnexpectedPayload userInfo:@{
                @"command": command,
                @"status": status,
                @"payload": payloadChunks
            }]);
        } else {
            responseBlock(status);
        }
    } onError:errorBlock];
}

- (void)sendCommand:(NSString *)command responseDataEncodingLength:(int)encodingLength onResponse:(SCIP20DataResponseBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock {
    [self sendCommand:command ignoringSpuriousResponses:NO onResponse:^(NSString *status, NSArray *payloadChunks) {
        NSError *error;
        NSData *data = [self dataByDecodingPayloadChunks:payloadChunks withEncodingLength:encodingLength error:&error];
        if (data) {
            responseBlock(status, data);
        } else {
            errorBlock(error);
        }
    } onError:errorBlock];
}

- (void)sendCommand:(NSString *)command onDictionaryResponse:(SCIP20DictionaryResponseBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock {
    [self sendCommand:command ignoringSpuriousResponses:NO onResponse:^(NSString *status, NSArray *payloadChunks) {
        NSError *error;
        NSDictionary *dictionary = [self dictionaryByDecodingPayloadChunks:payloadChunks error:&error];
        if (dictionary) {
            responseBlock(status, dictionary);
        } else {
            errorBlock(error);
        }
    } onError:errorBlock];
}

- (void)receiveStreamingResponseWithDataEncodingLength:(int)encodingLength onResponse:(SCIP20StreamingDataResponseBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock {
    [self readResponsePacketWithBlock:^(NSData *echoLine, NSString *status, NSArray *payloadChunks) {
        NSError *error;
        NSData *data = [self dataByDecodingPayloadChunks:payloadChunks withEncodingLength:encodingLength error:&error];
        if (data) {
            NSString *echo = commandFromEchoLine(echoLine);
            responseBlock(echo, status, data);
        } else {
            errorBlock(error);
        }
    } onError:errorBlock];
}

#pragma mark - Implementation details - send & receive helpers

- (void)sendCommand:(NSString *)command ignoringSpuriousResponses:(BOOL)ignoringSpuriousResponses onResponse:(SCIP20ResponsePacketBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock {
    NSData *commandPacket = [self commandPacketWithCommand:command];
    if (![self sendPacket:commandPacket withErrorBlock:errorBlock])
        return;
    [self readResponsePacketForCommandPacket:commandPacket ignoringSpuriousResponses:ignoringSpuriousResponses withBlock:responseBlock onError:errorBlock];
}

- (void)readResponsePacketForCommandPacket:(NSData *)commandPacket ignoringSpuriousResponses:(BOOL)ignoringSpuriousResponses withBlock:(SCIP20ResponsePacketBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock {
    __block BOOL waitingForResponse = YES;
    do {
        [self readResponsePacketWithBlock:^(NSData *echoLine, NSString *status, NSArray *payloadChunks) {
            if ([echoLine isEqualToData:commandPacket]) {
                responseBlock(status, payloadChunks);
                waitingForResponse = NO;
                return;
            }

            if (ignoringSpuriousResponses)
                return; // returns from this block but continues do/while loop

            waitingForResponse = NO;
            errorBlock([NSError errorWithDomain:SCIP20ErrorDomain code:SCIP20ErrorCode_Desynchronized userInfo:@{
                @"commandPacket": commandPacket,
                @"echoLine": echoLine,
                @"status": status,
                @"payloadChunks": payloadChunks
            }]);
        } onError:^(NSError *error) {
            waitingForResponse = NO;
            errorBlock(error);
        }];
    } while (waitingForResponse);
}

#pragma mark - Implementation details - low-level sending

- (NSData *)commandPacketWithCommand:(NSString *)command {
    return [[NSString stringWithFormat:@"%@;%llx\n", command, ++commandNumber_] dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)sendPacket:(NSData *)packet withErrorBlock:(SCIP20ErrorBlock)errorBlock {
    if ([channel_ sendData:packet withTimeout:_timeout])
        return YES;
    NSError *error = [NSError errorWithDomain:SCIP20ErrorDomain code:SCIP20ErrorCode_CommunicationFailed userInfo:@{
        NSUnderlyingErrorKey: channel_.error
    }];
    channel_.error = nil;
    errorBlock(error);
    return NO;
}

#pragma mark - Implementation details - low-level receiving

// This is the funnel method that all other methods call to read and process a complete response packet.
- (void)readResponsePacketWithBlock:(void (^)(NSData *echoLine, NSString *status, NSArray *payloadChunks))responseBlock onError:(SCIP20ErrorBlock)errorBlock {
    deadline_ = CFAbsoluteTimeGetCurrent() + _timeout;
    NSData *echoLine;
    NSString *status;
    NSMutableArray *payloadChunks;
    if (YES
        && [self readEchoLine:&echoLine onError:errorBlock]
        && [self readStatus:&status onError:errorBlock]
        && [self readPayload:&payloadChunks onError:errorBlock]) {
        responseBlock(echoLine, status, payloadChunks);
    }
}

- (BOOL)readEchoLine:(NSData **)echoLineOut onError:(SCIP20ErrorBlock)errorBlock {
    *echoLineOut = [channel_ readDataUntilTerminator:'\n' includingTerminator:YES withDeadline:deadline_];
    NSError *error = channel_.error;
    if (!error)
        return YES;
    channel_.error = nil;
    error = [NSError errorWithDomain:SCIP20ErrorDomain code:SCIP20ErrorCode_CommunicationFailed userInfo:@{
                NSUnderlyingErrorKey: error
             }];
    return NO;
}

- (BOOL)readStatus:(NSString **)statusOut onError:(SCIP20ErrorBlock)errorBlock {
    __block BOOL ok = NO;
    [self readChecksummedLineWithDataBlock:^(NSData *data) {
        *statusOut = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        ok = YES;
    } onEmptyLine:^{
        errorBlock([NSError errorWithDomain:SCIP20ErrorDomain code:SCIP20ErrorCode_MissingStatusLine userInfo:nil]);
    } onError:errorBlock];
    return ok;
}

- (BOOL)readPayload:(NSMutableArray **)payloadChunksOut onError:(SCIP20ErrorBlock)errorBlock {
    NSMutableArray *chunks = [[NSMutableArray alloc] init];
    *payloadChunksOut = chunks;
    __block BOOL ok = YES;
    __block BOOL shouldKeepReading = NO;
    do {
        [self readChecksummedLineWithDataBlock:^(NSData *data) {
            [chunks addObject:data];
            shouldKeepReading = YES;
        } onEmptyLine:^{
            shouldKeepReading = NO;
        } onError:^(NSError *error) {
            shouldKeepReading = NO;
            errorBlock(error);
        }];
    } while (ok && shouldKeepReading);
    return ok;
}

// I return YES if I called `dataBlock`.  I return NO if I called `errorBlock` or read an empty line.
- (void)readChecksummedLineWithDataBlock:(void (^)(NSData *data))dataBlock onEmptyLine:(void (^)())emptyBlock onError:(SCIP20ErrorBlock)errorBlock {
    NSData *data = [channel_ readDataUntilTerminator:'\n' includingTerminator:NO withDeadline:deadline_];
    NSError *error = channel_.error;
    if (error) {
        channel_.error = nil;
        error = [NSError errorWithDomain:SCIP20ErrorDomain code:SCIP20ErrorCode_CommunicationFailed userInfo:@{
            NSUnderlyingErrorKey: error
        }];
        errorBlock(error);
    } else if (data.length == 0) {
        if (emptyBlock) {
            emptyBlock();
        }
    } else {
        // Discard checksum.
        data = [data subdataWithRange:NSMakeRange(0, data.length - 1)];
        dataBlock(data);
    }
}

#pragma mark - Implementation details - payload decoding

- (NSData *)dataByDecodingPayloadChunks:(NSArray *)chunks withEncodingLength:(int)encodingLength error:(NSError **)errorOut {
    NSMutableData *data = [[NSMutableData alloc] init];
    NSUInteger bytesToDecode = encodingLength;
    NSUInteger decodedValue = 0;
    for (NSData *chunk in chunks) {
        char const *p = chunk.bytes;
        for (NSUInteger i = 0; i < chunk.length; ++i, ++p) {
            decodedValue = (decodedValue << 6) | (*p - 0x30);
            --bytesToDecode;
            if (bytesToDecode == 0) {
                [data appendBytes:&decodedValue length:sizeof decodedValue];
                bytesToDecode = encodingLength;
            }
        }
    }
    if (bytesToDecode > 0) {
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:SCIP20ErrorDomain code:SCIP20ErrorCode_PayloadDecodingFailed userInfo:@{
                @"payload": chunks,
                @"encodingLength": @(encodingLength)
            }];
        }
        data = nil;
    }
    return data;
}

- (NSDictionary *)dictionaryByDecodingPayloadChunks:(NSArray *)chunks error:(NSError **)errorOut {
    NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithCapacity:chunks.count];
    for (NSData *chunk in chunks) {
        if (![self parseChunk:chunk intoDictionary:dictionary]) {
            if (errorOut) {
                *errorOut = [NSError errorWithDomain:SCIP20ErrorDomain code:SCIP20ErrorCode_PayloadDecodingFailed userInfo:@{
                    @"payload": chunks,
                    @"failedChunk": chunk
                }];
            }
            return nil;
        }
    }
    return dictionary;
}

- (BOOL)parseChunk:(NSData *)chunk intoDictionary:(NSMutableDictionary *)dictionary {
    NSString *string = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
    NSRange colonRange = [string rangeOfString:@":"];
    if (colonRange.location == NSNotFound)
        return NO;
    static NSCharacterSet *whitespace;
    static NSMutableCharacterSet *whitespaceAndSemicolon;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        whitespace = [NSCharacterSet whitespaceCharacterSet];
        whitespaceAndSemicolon = [whitespace mutableCopy];
        [whitespaceAndSemicolon addCharactersInString:@";"];
    });

    NSString *key = [[string substringToIndex:colonRange.location] stringByTrimmingCharactersInSet:whitespace];
    NSString *value = [[string substringFromIndex:colonRange.location + 1] stringByTrimmingCharactersInSet:whitespaceAndSemicolon];
    dictionary[key] = value;
    return YES;
}

@end
