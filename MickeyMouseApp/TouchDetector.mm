//  Copyright (c) 2012 Rob Mayoff. All rights reserved.

#import "DqdObserverSet.h"
#import "Lidar2D.h"
#import "TouchDetector.h"
#import <vector>

using std::vector;

static NSUInteger const kReportsNeededForUntouchedFieldCalibration = 20;

@interface TouchDetector () <Lidar2DObserver>
@end

@implementation TouchDetector {
    Lidar2D *device_;
    DqdObserverSet *observers_;

    void (^distancesReportHandler_)(Lidar2DDistance const *distances);

    // Each element of `untouchedFieldDistances_` corresponds to one ray and is the minimum distance at which I consider that ray to be uninterrupted by a touch.
    vector<Lidar2DDistance> untouchedFieldDistances_;

    NSUInteger reportsReceivedForUntouchedFieldCalibration_;

    // `reportsNeededForTouchCalibration_` is the number of reports I need to receive to finish calibrating the current touch point.
    NSUInteger reportsNeededForTouchCalibration_;

    // Each element of `calibrationDistanceSumsStorage_` corresponds to one ray and is the sum of the distances reported for that ray since I started calibrating the current touch.
    vector<Lidar2DDistance> calibrationDistanceSums_;
    
    // `calibrationReportsCount_` is the number of distance reports I have added into `calibrationDistanceSumsStorage_` since I started calibrating the current touch.
    NSUInteger calibrationReportsCount_;

    NSUInteger touchCalibrationCount_;
    CGPoint currentCalibrationPoint_;
}

#pragma mark - Public API

- (void)dealloc {
    [device_ removeObserver:self];
}

- (id)initWithDevice:(Lidar2D *)device {
    if ((self = [super init])) {
        device_ = device;
        [device addObserver:self];
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
    reportsReceivedForUntouchedFieldCalibration_ = 0;
    self.state = TouchDetectorState_CalibratingUntouchedField;

    __weak TouchDetector *me = self;
    distancesReportHandler_ = ^(Lidar2DDistance const *distances) {
        [me calibrateUntouchedFieldWithDistances:distances];
    };
}

- (BOOL)canStartCalibratingTouchAtPoint {
    return ![self isBusy] && device_.isConnected && ![self needsUntouchedFieldCalibration];
}

- (void)startCalibratingTouchAtPoint:(CGPoint)point {
    [self requireNotBusy];
    currentCalibrationPoint_ = point;
    calibrationReportsCount_ = 0;
    self.state = TouchDetectorState_CalibratingTouch;

    __weak TouchDetector *me = self;
    distancesReportHandler_ = ^(Lidar2DDistance const *distances) {
        [me calibrateTouchWithDistances:distances];
    };
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
    block(untouchedFieldDistances_.data(), untouchedFieldDistances_.size());
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
    return reportsReceivedForUntouchedFieldCalibration_ < kReportsNeededForUntouchedFieldCalibration;
}

- (void)calibrateUntouchedFieldWithDistances:(Lidar2DDistance const *)distances {
    if (reportsReceivedForUntouchedFieldCalibration_ == 0) {
        [self resetUntouchedFieldDistances];
    } else if (reportsReceivedForUntouchedFieldCalibration_ == kReportsNeededForUntouchedFieldCalibration) {
        [NSException raise:NSInternalInconsistencyException format:@"%s called with reportsNeededForUntouchedFieldCalibration_ == %ld == kReportsNeededForUntouchedFieldCalibration", __func__, reportsReceivedForUntouchedFieldCalibration_];
    }

    [self updateUntouchedFieldDistancesWithReportedDistances:distances];
    [self updateReportsReceivedForUntouchedFieldCalibration];
}

- (void)resetUntouchedFieldDistances {
    untouchedFieldDistances_.assign(device_.rayCount, Lidar2DDistance_MAX);
}

- (void)updateUntouchedFieldDistancesWithReportedDistances:(Lidar2DDistance const *)distances {
    for (NSUInteger i = 0, l = MIN(device_.rayCount, untouchedFieldDistances_.size()); i < l; ++i) {
        untouchedFieldDistances_[i] = MIN(untouchedFieldDistances_[i], distances[i]);
    }
}

- (void)updateReportsReceivedForUntouchedFieldCalibration {
    ++reportsReceivedForUntouchedFieldCalibration_;
    if (reportsReceivedForUntouchedFieldCalibration_ == kReportsNeededForUntouchedFieldCalibration) {
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
    for (auto p = untouchedFieldDistances_.begin(); p != untouchedFieldDistances_.end(); ++p) {
        *p *= 0.95;
    }
}

#pragma mark - Touch calibration details

- (BOOL)needsTouchCalibration {
    return touchCalibrationCount_ < 4;
}

- (void)calibrateTouchWithDistances:(Lidar2DDistance const *)distances {
    abort(); // xxx
}

@end
