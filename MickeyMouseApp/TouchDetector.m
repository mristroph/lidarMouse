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

@interface TouchDetector () <Lidar2DObserver>
@end

@implementation TouchDetector {
    Lidar2D *device_;
    DqdObserverSet *observers_;

    void (^distancesReportHandler_)(Lidar2DDistance const *distances);

    NSUInteger reportsNeededForUntouchedFieldCalibration_;
    uint32_t *untouchedFieldDistances_;
    NSUInteger untouchedFieldDistancesCount_;

    NSMutableData *calibrationPointStorage_;
    NSMutableData *calibrationMeasurementStorage_;
    NSUInteger touchCalibrationCount_;
    CGPoint currentCalibrationPoint_;
}

#pragma mark - Public API

- (void)dealloc {
    [device_ removeObserver:self];
    [self resetUntouchedFieldCalibrationParameters];
}

- (id)initWithDevice:(Lidar2D *)device {
    if ((self = [super init])) {
        device_ = device;
        [device addObserver:self];
        [self resetUntouchedFieldCalibrationParameters];
        [self setAppropriateStateBecauseCalibrationFinished];
    }
    return self;
}

@synthesize state = _state;

- (BOOL)canStartCalibratingUntouchedField {
    return ![self isBusy] && device_.isConnected;
}

- (void)startCalibratingUntouchedField {
    [self requireNotBusy];
    [self resetUntouchedFieldCalibrationParameters];
    [self allocateUntouchedFieldDistances];
    self.state = TouchDetectorState_CalibratingUntouchedField;

    __weak TouchDetector *me = self;
    distancesReportHandler_ = ^(Lidar2DDistance const *distances) {
        TouchDetector *self = me;
        [self calibrateUntouchedFieldWithDistances:distances];
    };
}

- (BOOL)canStartCalibratingTouchAtPoint {
    return ![self isBusy] && device_.isConnected && ![self needsUntouchedFieldCalibration];
}

- (void)startCalibratingTouchAtPoint:(CGPoint)point {
    [self requireNotBusy];
    currentCalibrationPoint_ = point;
    self.state = TouchDetectorState_CalibratingTouch;
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

#pragma mark - Lidar2DObserver protocol

-  (void)lidar2DDidTerminate:(Lidar2D *)device {
    (void)device;
    // Nothing to do
}

- (void)lidar2d:(Lidar2D *)device didReceiveDistances:(const Lidar2DDistance *)distances {
    (void)device;
    if (distancesReportHandler_) {
        distancesReportHandler_(distances);
    }
}

#pragma mark - Implementation details - general state management

- (void)setState:(TouchDetectorState)state {
    if (_state != state) {
        _state = state;
        [self notifyObserverOfCurrentState:observers_.proxy];
    }
}

- (void)setAppropriateStateBecauseCalibrationFinished {
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

- (void)resetUntouchedFieldCalibrationParameters {
    reportsNeededForUntouchedFieldCalibration_ = 20;
    free(untouchedFieldDistances_);
    untouchedFieldDistances_ = NULL;
    untouchedFieldDistancesCount_ = 0;
}

- (void)allocateUntouchedFieldDistances {
    NSUInteger count = device_.rayCount;
    untouchedFieldDistances_ = malloc(count * sizeof *untouchedFieldDistances_);
    for (NSUInteger i = 0; i < count; ++i) {
        untouchedFieldDistances_[i] = UINT32_MAX;
    }
    untouchedFieldDistancesCount_ = count;
}

- (void)calibrateUntouchedFieldWithDistances:(Lidar2DDistance const *)distances {
    if (reportsNeededForUntouchedFieldCalibration_ == 0) {
        [NSException raise:NSInternalInconsistencyException format:@"%s called with reportsNeededForUntouchedFieldCalibration_ == 0", __func__];
    }

    [self updateUntouchedFieldDistancesWithReportedDistances:distances];
    [self updateReportsNeededForUntouchedFieldCalibration];
}

- (void)updateUntouchedFieldDistancesWithReportedDistances:(Lidar2DDistance const *)distances {
    for (NSUInteger i = 0; i < untouchedFieldDistancesCount_; ++i) {
        untouchedFieldDistances_[i] = MIN(untouchedFieldDistances_[i], distances[i]);
    }
}

- (void)updateReportsNeededForUntouchedFieldCalibration {
    --reportsNeededForUntouchedFieldCalibration_;
    if (reportsNeededForUntouchedFieldCalibration_ == 0) {
        [self finishCalibratingUntouchedField];
    }
}

- (void)finishCalibratingUntouchedField {
    distancesReportHandler_ = nil;
    [self tweakUntouchedFieldDistances];
    [observers_.proxy touchDetectorDidFinishCalibratingUntouchedField:self];
    [self setAppropriateStateBecauseCalibrationFinished];
}

- (void)tweakUntouchedFieldDistances {
    for  (NSUInteger i = 0; i < untouchedFieldDistancesCount_; ++i) {
        untouchedFieldDistances_[i] *= 0.95;
    }
}

#pragma mark - Touch calibration details

- (BOOL)needsTouchCalibration {
    return touchCalibrationCount_ < 4;
}

@end
