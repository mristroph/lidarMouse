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
    id<Lidar2DProxy> deviceProxy_;
    DqdObserverSet *observers_;

    CGPoint currentCalibrationPoint_;

    BOOL hasCalibratedUntouchedField_ : 1;
}

#pragma mark - Public API

- (id)initWithLidar2DProxy:(id<Lidar2DProxy>)deviceProxy {
    if ((self = [super init])) {
        deviceProxy_ = deviceProxy;
        [self setAppropriateState];
    }
    return self;
}

@synthesize state = _state;

- (void)startCalibratingUntouchedField {
    [self requireNotBusy];
    self.state = TouchDetectorState_CalibratingUntouchedField;
    [deviceProxy_ performBlock:^(id<Lidar2D> device) {
        [self calibrateUntouchedFieldWithDevice:device];
    }];
}

- (void)startCalibratingTouchAtPoint:(CGPoint)point {
    [self requireNotBusy];
    currentCalibrationPoint_ = point;
    self.state = TouchDetectorState_CalibratingTouch;
    [deviceProxy_ performBlock:^(id<Lidar2D> device) {
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
    return !hasCalibratedUntouchedField_;
}

- (void)calibrateUntouchedFieldWithDevice:(id<Lidar2D>)device {
    abort(); // xxx

    [self performSelectorOnMainThread:@selector(finishCalibratingUntouchedField) withObject:nil waitUntilDone:NO];
}

- (void)finishCalibratingUntouchedField {
    abort(); // xxx multiply all distances by 0.95

    hasCalibratedUntouchedField_ = YES;
    [self setAppropriateState];
}

#pragma mark - Touch calibration details

- (BOOL)needsTouchCalibration {
    abort(); // xxx
}

- (void)calibrateTouchWithDevice:(id<Lidar2D>)device {
    abort(); // xxx

    [self performSelectorOnMainThread:@selector(setAppropriateState) withObject:nil waitUntilDone:NO];
}

@end
