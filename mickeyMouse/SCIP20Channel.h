/*
Created by Rob Mayoff on 12/9/12.
Copyright (c) 2012 Rob Mayoff. All rights reserved.
*/

#import <Foundation/Foundation.h>

extern NSString *const SCIP20ErrorDomain;

typedef enum {
    SCIP20ErrorCode_Unknown,
    SCIP20ErrorCode_CommunicationFailed,
    SCIP20ErrorCode_MissingStatusLine,
    SCIP20ErrorCode_MissingTimestampLine,
    SCIP20ErrorCode_Desynchronized,
    SCIP20ErrorCode_UnexpectedPayload,
    SCIP20ErrorCode_PayloadDecodingFailed
} SCIP20ErrorCode;

@class ByteChannel;

typedef void (^SCIP20ErrorBlock)(NSError *error);
typedef void (^SCIP20EmptyResponseBlock)(NSString *status);
typedef void (^SCIP20DataResponseBlock)(NSString *status, NSData *data);
typedef void (^SCIP20DictionaryResponseBlock)(NSString *status, NSDictionary *info);
typedef void (^SCIP20StreamingDataResponseBlock)(NSString *command, NSString *status, NSUInteger timestamp, NSData *data);

@interface SCIP20Channel : NSObject

- (id)initWithByteChannel:(ByteChannel *)byteChannel;

// This is the amount of time I allow for receiving a response before giving up and returning a timeout error.  The default is 1 second.
@property (nonatomic) CFTimeInterval timeout;

// Send the given command (which must not include the “String Characters” field or terminating newline.  I expect a response with no data.  If I receive a valid response, I pass its status to `responseBlock`.  Otherwise, I call `errorBlock`.  If `ignoringSpuriousResponses` is YES, I ignore responses that don't match `command` instead of considering them errors.  You should set this when sending a command to stop streaming data.
- (void)sendCommand:(NSString *)command ignoringSpuriousResponses:(BOOL)ignoringSpuriousResponses onEmptyResponse:(SCIP20EmptyResponseBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock;

// Send the given command (which must not include the “String Characters” field or terminating newline.  I expect a response with data encoded in the 2-character, 3-character, or 4-character encoding, depending on the `encodingLength` argument.  If I receive a valid response, I pass the response status and decoded data to `responseBlock`.  Otherwise, I call `errorBlock`.
- (void)sendCommand:(NSString *)command responseDataEncodingLength:(int)encodingLength onResponse:(SCIP20DataResponseBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock;

// Send the given command (which must not include the “String Characters” field or terminating newline.  I expect a response with a dictionary. If I receive a valid response, I pass the response status and decoded dictionary to `responseBlock`.  Otherwise, I call `errorBlock`.
- (void)sendCommand:(NSString *)command onDictionaryResponse:(SCIP20DictionaryResponseBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock;

// I try to receive an encoded data response without sending a command first.  If I receive a valid response, I pass the echoed command, the response status and the decoded data to `responseBlock`.  Otherwise, I call `errorBlock`.
- (void)receiveStreamingResponseWithDataEncodingLength:(int)encodingLength onResponse:(SCIP20StreamingDataResponseBlock)responseBlock onError:(SCIP20ErrorBlock)errorBlock;

@end
