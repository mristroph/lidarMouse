/*
Created by Rob Mayoff on 7/30/12.
This file is public domain.
*/

#import "DqdObserverSet.h"
#import <objc/runtime.h>

@interface DqdObserverSetMessageProxy : NSObject
@property (nonatomic, unsafe_unretained) DqdObserverSet *observerSet;
@end

static NSMutableSet *nonRetainingSet(void) {
    CFSetCallBacks callbacks = {
        .version = 0,
        .retain = NULL,
        .release = NULL,
        .copyDescription = kCFTypeSetCallBacks.copyDescription,
        .equal = kCFTypeSetCallBacks.equal,
        .hash = kCFTypeSetCallBacks.hash

    };
    return CFBridgingRelease(CFSetCreateMutable(NULL, 0, &callbacks));
}

@implementation DqdObserverSet {
    NSMutableSet *observers_;
    NSMutableSet *pendingAdditions_;
    NSMutableSet *pendingDeletions_;
    BOOL isForwarding_;
}

#pragma mark - Public API

@synthesize proxy = _proxy;
@synthesize protocol = _protocol;

- (id)init {
    NSLog(@"I only understand -[%@ initWithProtocol:], not -[%@ init].", self.class, self.class);
    [self doesNotRecognizeSelector:_cmd]; abort();
}

- (id)initWithProtocol:(Protocol *)protocol {
    if ((self = [super init])) {
        _protocol = protocol;
        _proxy = [[DqdObserverSetMessageProxy alloc] init];
        [_proxy setObserverSet:self];
    }
    return self;
}

- (void)addObserver:(id)observer {
    if (isForwarding_ && pendingDeletions_) {
        [pendingDeletions_ removeObject:observer];
    }
    
    __strong NSMutableSet **set = isForwarding_ ? &pendingAdditions_ : &observers_;

    if (!*set) {
        *set = nonRetainingSet();
    }
    [*set addObject:observer];
}

- (void)removeObserver:(id)observer {
    if (isForwarding_) {
        if (pendingAdditions_) {
            [pendingAdditions_ removeObject:observer];
        }
        if (!pendingDeletions_) {
            pendingDeletions_ = nonRetainingSet();
        }
        [pendingDeletions_ addObject:observer];
    } else {
        [observers_ removeObject:observer];
    }
}

#pragma mark - DqdObserverSetMessageProxy API

- (NSMethodSignature *)protocolMethodSignatureForSelector:(SEL)selector {
    NSAssert(_protocol != nil, @"%@ protocol not set", self);
    struct objc_method_description description = protocol_getMethodDescription(_protocol, selector, YES, YES);
    if (!description.name) {
        description = protocol_getMethodDescription(_protocol, selector, NO, YES);
    }
    NSAssert(description.name, @"%@ couldn't find selector %s in protocol %s", self, sel_getName(selector), protocol_getName(_protocol));
    return [NSMethodSignature signatureWithObjCTypes:description.types];
}

- (void)forwardInvocationToObservers:(NSInvocation *)invocation {
    NSAssert(!isForwarding_, @"%@ asked to forward a message to observers recursively", self);

    isForwarding_ = YES;
    @try {
        SEL selector = invocation.selector;
        for (id observer in observers_) {
            if (pendingDeletions_ && [pendingDeletions_ containsObject:observer])
                continue;
            if ([observer respondsToSelector:selector]) {
                [invocation invokeWithTarget:observer];
            }
        }
    }
    @finally {
        isForwarding_ = NO;

        if (pendingAdditions_) {
            [observers_ unionSet:pendingAdditions_];
            pendingAdditions_ = nil;
        }
        
        if (pendingDeletions_) {
            [observers_ minusSet:pendingDeletions_];
            pendingDeletions_ = nil;
        }
    }
}

@end

@implementation DqdObserverSetMessageProxy

@synthesize observerSet = _observerSet;

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [self.observerSet protocolMethodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    [self.observerSet forwardInvocationToObservers:anInvocation];
}

@end

