//
//  TouchDetector.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/13/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "DqdObserverSet.h"
#import "Lidar2D.h"
#import "TouchDetector.h"

@implementation TouchDetector {
    Lidar2D *device_;
    DqdObserverSet *observers_;

    uint32_t *untouchedFieldDistances_;
    NSUInteger untouchedFieldDistancesCount_;

    CGPoint currentCalibrationPoint_;
}

#pragma mark - Public API

- (void)dealloc {
    [self deallocateUntouchedFieldDistances];
}

- (id)initWithDevice:(Lidar2D *)device {
    if ((self = [super init])) {
        device_ = device;
        [self setAppropriateState];
    }
    return self;
}

@synthesize state = _state;

- (void)startCalibratingUntouchedField {
    [self requireNotBusy];
    self.state = TouchDetectorState_CalibratingUntouchedField;
    [device_ performBlock:^(id<Lidar2D> device) {
        [self calibrateUntouchedFieldWithDevice:device];
    }];
}

- (void)startCalibratingTouchAtPoint:(CGPoint)point {
    [self requireNotBusy];
    currentCalibrationPoint_ = point;
    self.state = TouchDetectorState_CalibratingTouch;
    [device_ performBlock:^(id<Lidar2D> device) {
        [self calibrateTouchWithDevice:device];
    }];
}

- (void)addObserver:(id<TouchDetectorObserver>)observer {
    if (!observers_) {
        observers_ = [[DqdObserverSet alloc] initWithProtocol:@protocol(TouchDetectorObserver)];
    }
    [observers_ addObserver:observer];
}

- (void)removeObserver:(id<TouchDetectorObserver>)observer {
    [observers_ removeObserver:observer];
}

- (void)notifyObserverOfCurrentState:(id<TouchDetectorObserver>)observer {
    switch (_state) {
        case TouchDetectorState_AwaitingUntouchedFieldCalibration:
            [observer touchDetectorIsAwaitingUntouchedFieldCalibration:self];
            break;
        case TouchDetectorState_CalibratingUntouchedField:
            [observer touchDetectorIsCalibratingUntouchedField:self];
            break;
        case TouchDetectorState_AwaitingTouchCalibration:
            [observer touchDetectorIsAwaitingTouchCalibration:self];
            break;
        case TouchDetectorState_CalibratingTouch:
            [observer touchDetector:self isCalibratingTouchAtPoint:currentCalibrationPoint_];
            break;
        case TouchDetectorState_DetectingTouches:
            [observer touchDetectorIsDetectingTouches:self];
            break;
    }
}

- (void)getUntouchedFieldDistancesWithBlock:(void (^)(uint32_t const *, NSUInteger))block {
    block(untouchedFieldDistances_, untouchedFieldDistancesCount_);
}

#pragma mark - Implementation details - general state management

- (void)setState:(TouchDetectorState)state {
    if (_state != state) {
        _state = state;
        [self notifyObserverOfCurrentState:observers_.proxy];
    }
}

- (void)setAppropriateState {
    self.state = [self needsUntouchedFieldCalibration] ? TouchDetectorState_AwaitingUntouchedFieldCalibration
        : [self needsTouchCalibration] ? TouchDetectorState_AwaitingTouchCalibration
        : TouchDetectorState_DetectingTouches;
}

// When this returns YES, it means I'm doing something that reads from the device, so I can't start anything new that reads from the device.
- (BOOL)isBusy {
    switch (_state) {
        case TouchDetectorState_AwaitingUntouchedFieldCalibration: return NO;
        case TouchDetectorState_CalibratingUntouchedField: return YES;
        case TouchDetectorState_AwaitingTouchCalibration: return NO;
        case TouchDetectorState_CalibratingTouch: return YES;
        case TouchDetectorState_DetectingTouches: return NO;
    }
}

// I throw an exception if I'm busy.
- (void)requireNotBusy {
    if ([self isBusy]) {
        [NSException raise:NSInternalInconsistencyException format:@"received %s while in state %@", __func__, [self stateString]];
    }
}

- (NSString *)stateString {
#define StateString(State) case TouchDetectorState_##State: return @#State
    switch (_state) {
        StateString(AwaitingUntouchedFieldCalibration);
        StateString(CalibratingUntouchedField);
        StateString(AwaitingTouchCalibration);
        StateString(CalibratingTouch);
        StateString(DetectingTouches);
    }
}

#pragma mark - Untouched field calibration details

- (BOOL)needsUntouchedFieldCalibration {
    return untouchedFieldDistances_ == NULL;
}

- (void)calibrateUntouchedFieldWithDevice:(id<Lidar2D>)device {
    [self deallocateUntouchedFieldDistances];
    [self allocateUntouchedFieldDistancesWithDevice:device];

    __block NSUInteger scansNeeded = 20;
    while (scansNeeded > 0) {
        [device forEachStreamingDataSnapshot:^(uint32_t const *distances, BOOL *stop) {
            [self calibrateUntouchedFieldWithDistances:distances device:device];
            *stop = --scansNeeded == 0;
        }];

        if (device.error) {
            NSLog(@"device error: %@", device.error);
            device.error = nil;

            if (scansNeeded > 0) {
                sleep(1);
            }
        }
    }

    [self polishUntouchedFieldDistancesWithDevice:device];
    [self performSelectorOnMainThread:@selector(setAppropriateState) withObject:nil waitUntilDone:NO];
}

- (void)calibrateUntouchedFieldWithDistances:(uint32 const *)distances device:(id<Lidar2D>)device {
    (void)device; // enforces this only being called on device queue

    for (NSUInteger i = 0; i < untouchedFieldDistancesCount_; ++i) {
        untouchedFieldDistances_[i] = MIN(untouchedFieldDistances_[i], distances[i]);
    }
}

- (void)polishUntouchedFieldDistancesWithDevice:(id<Lidar2D>)device {
    (void)device; // enforces this only being called on device queue
    for  (NSUInteger i = 0; i < untouchedFieldDistancesCount_; ++i) {
        untouchedFieldDistances_[i] *= 0.95;
    }
}

- (void)allocateUntouchedFieldDistancesWithDevice:(id<Lidar2D>)device {
    NSUInteger count = device.rayCount;
    untouchedFieldDistances_ = malloc(count * sizeof *untouchedFieldDistances_);
    for (NSUInteger i = 0; i < count; ++i) {
        untouchedFieldDistances_[i] = UINT32_MAX;
    }
    untouchedFieldDistancesCount_ = count;
}

- (void)deallocateUntouchedFieldDistances {
    free(untouchedFieldDistances_);
    untouchedFieldDistances_ = NULL;
    untouchedFieldDistancesCount_ = 0;
}

#pragma mark - Touch calibration details

- (BOOL)needsTouchCalibration {
    abort(); // xxx
}

- (void)calibrateTouchWithDevice:(id<Lidar2D>)device {
    (void)device;
    abort(); // xxx

    [self performSelectorOnMainThread:@selector(setAppropriateState) withObject:nil waitUntilDone:NO];
}

@end
