/*
Created by Rob Mayoff on 7/30/12.
This file is public domain.
*/

#import <Foundation/Foundation.h>

/**
## DqdObserverSet

I manage a set of observers and provide an easy way to send messages to all of the observers in the set.

To avoid retain cycles, I don't retain the observers.  I assume that observers retain you, and you retain me.

To use me, you need to define a protocol containing the messages you want to send to the observers.  For example, here's an observer-style protocol:

    @class Model;
    @protocol ModelObserver
    
    @required
    - (void)model:(Model *)model didChangeImportantObject:(NSObject *)object;
    
    @optional
    - (void)modelDidTick:(Model *)model;
    - (void)model:(Model *)model didChangeTrivialDetail:(NSObject *)detail;
    
    @end

You initialize me by sending me `initWithProtocol:`, passing the protocol as an argument:

    DqdObserverSet *observers = [[DqdObserverSet alloc] initWithProtocol:@protocol(ModelObserver)];

You can then add observers to me by sending me `addObserver:` messages, and remove them by sending me `removeObserver:` messages.  When you're ready to send a message to the observers, send it to my message-forwarding proxy, using my `proxy` property:

    [observers.proxy model:self didChangeImportantObject:someObject];

If it's a required message, I'll send it to all of the observers.  Any observer that doesn't respond to the message selector will raise an exception!

You can send an optional message the same way:

    [observers.proxy model:self didChangeTrivialDetail:someObject];

The proxy will only forward the optional message to those observers that respond to the message selector.

The proxy can forward messages with any signature, so you for example can also send a message with only one argument:

    [observers.proxy modelDidTick:self];

*/

@interface DqdObserverSet : NSObject

- (id)initWithProtocol:(Protocol *)protocol;

/**
The protocol adopted by the observers I manage.
*/
@property (nonatomic, strong, readonly) Protocol *protocol;

/**
Add `observer` to my set, if it's not there already.  Otherwise, do nothing.

If you send me this message while I'm sending a message to observers, and I didn't already have `observer` in my set, I won't send the current message to `observer`.
*/
- (void)addObserver:(id)observer;

/**
Remove `observer` from my set, if it's there.  Otherwise, do nothing.

If you send me this message while I'm sending a message to observers, and I have `observer` in my set but haven't sent him the current message yet, I won't send him the current message at all.
*/
- (void)removeObserver:(id)observer;

/**
An object that forwards messages to my observers.  If you send it an optional message, it only forwards the message to those observers that respond to the message selector.
*/
@property (nonatomic, strong, readonly) id proxy;

@end
