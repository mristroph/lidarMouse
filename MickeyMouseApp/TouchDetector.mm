//  Copyright (c) 2012 Rob Mayoff. All rights reserved.

#import "DqdObserverSet.h"
#import "Lidar2D.h"
#import "TouchDetector.h"
#import <vector>

using std::vector;

static Lidar2DDistance const kMinimumDistance = 20;
static NSUInteger const kReportsNeededForUntouchedFieldCalibration = 20;
static NSUInteger const kTouchCalibrationsNeeded = 3;
static NSUInteger const kReportsNeededForTouchCalibration = 20;
static NSUInteger const kDistancesNeededForRayToBeTreatedAsTouch = 15;

static BOOL isValidDistance(Lidar2DDistance distance) {
    return distance >= kMinimumDistance && distance != Lidar2DDistance_MAX;
}

static Lidar2DDistance correctedDistance(Lidar2DDistance distance) {
    return isValidDistance(distance) ? distance : Lidar2DDistance_MAX;
}

// To use `dgels_` to solve for the affine transform, I need to augment each point from the sensor with a constant 1, which is the coefficient of the translation element of the transform.
struct SensorPoint {
    __CLPK_doublereal x;
    __CLPK_doublereal y;
    __CLPK_doublereal one;
    SensorPoint(__CLPK_doublereal x_, __CLPK_doublereal y_) : x(x_), y(y_), one(1) { }
};

struct ScreenPoint {
    __CLPK_doublereal x;
    __CLPK_doublereal y;
    ScreenPoint(__CLPK_doublereal x_, __CLPK_doublereal y_) : x(x_), y(y_) { }
};

@interface TouchDetector () <Lidar2DObserver>
@end

@implementation TouchDetector {
    Lidar2D *device_;
    DqdObserverSet *observers_;

    void (^distancesReportHandler_)(Lidar2DDistance const *distances);

    // Each element of `untouchedFieldDistances_` corresponds to one ray and is the minimum distance at which I consider that ray to be uninterrupted by a touch.
    vector<Lidar2DDistance> untouchedFieldDistances_;

    NSUInteger reportsReceivedForUntouchedFieldCalibration_;

    // Each element of `touchDistanceSums_` corresponds to one ray and is the sum of the valid distances reported for that ray since I started calibrating the current touch.
    vector<Lidar2DDistance> touchDistanceSums_;

    // Each element of `touchDistanceCounts_` corresponds to one ray and is the number of valid distances reported for that ray since I started calibrating the current touch.
    vector<uint16_t> touchDistanceCounts_;

    NSUInteger reportsReceivedForTouchCalibration_;

    vector<SensorPoint> sensorPointsForTouchCalibration_;
    vector<ScreenPoint> screenPointsForTouchCalibration_;
    
    CGPoint currentCalibrationPoint_;

    CGAffineTransform sensorToScreenTransform_;
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
    reportsReceivedForTouchCalibration_ = 0;
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
        [NSException raise:NSInternalInconsistencyException format:@"%s called with reportsReceivedForUntouchedFieldCalibration_ == %ld == kReportsNeededForUntouchedFieldCalibration", __func__, reportsReceivedForUntouchedFieldCalibration_];
    }

    [self updateUntouchedFieldDistancesWithReportedDistances:distances];
    [self updateReportsReceivedForUntouchedFieldCalibration];
}

- (void)resetUntouchedFieldDistances {
    untouchedFieldDistances_.assign(device_.rayCount, Lidar2DDistance_MAX);
}

- (void)updateUntouchedFieldDistancesWithReportedDistances:(Lidar2DDistance const *)distances {
    for (NSUInteger i = 0, l = MIN(device_.rayCount, untouchedFieldDistances_.size()); i < l; ++i) {
        untouchedFieldDistances_[i] = MIN(untouchedFieldDistances_[i], correctedDistance(distances[i]));
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
    return sensorPointsForTouchCalibration_.size() < kTouchCalibrationsNeeded;
}

- (void)calibrateTouchWithDistances:(Lidar2DDistance const *)distances {
    if (reportsReceivedForTouchCalibration_ == 0) {
        [self resetTouchDistanceSums];
    } else if (reportsReceivedForTouchCalibration_ == kReportsNeededForTouchCalibration) {
        [NSException raise:NSInternalInconsistencyException format:@"%s called with reportsReceivedForTouchCalibration_ == %ld == kReportsNeededForUntouchedFieldCalibration", __func__, reportsReceivedForTouchCalibration_];
    }

    [self updateTouchDistancesWithReportedDistances:distances];
    [self updateReportsReceivedForTouchCalibration];
}

- (void)resetTouchDistanceSums {
    NSUInteger count = device_.rayCount;
    touchDistanceSums_.assign(count, Lidar2DDistance_MAX);
    touchDistanceCounts_.assign(count, 0);
}

- (void)updateTouchDistancesWithReportedDistances:(Lidar2DDistance const *)distances {
    NSUInteger l = MIN(touchDistanceSums_.size(), device_.rayCount);
    for (NSUInteger i = 0; i < l; ++i) {
        Lidar2DDistance distance = distances[i];
        if (isValidDistance(distance)) {
            touchDistanceSums_[i] += distance;
            ++touchDistanceCounts_[i];
        }
    }
}

- (void)updateReportsReceivedForTouchCalibration {
    ++reportsReceivedForTouchCalibration_;
    if (reportsReceivedForTouchCalibration_ == kReportsNeededForTouchCalibration) {
        [self finishCalibratingTouch];
    }
}

- (void)finishCalibratingTouch {
    vector<BOOL> rayWasTouched;
    [self computeTouchedRays:rayWasTouched];
    __block NSUInteger touchesFound = 0;
    __block NSUInteger rayIndex;
    [self forEachSweepInTouchedRays:rayWasTouched do:^(NSUInteger middleRayIndex) {
        ++touchesFound;
        rayIndex = middleRayIndex;
    }];

    if (touchesFound == 0) {
        [observers_.proxy touchDetector:self didFinishCalibratingTouchAtPoint:currentCalibrationPoint_ withResult:TouchCalibrationResult_NoTouchDetected];
    } else if (touchesFound == 1) {
        [self recordCalibratedTouchAtRayIndex:rayIndex];
    } else {
        [observers_.proxy touchDetector:self didFinishCalibratingTouchAtPoint:currentCalibrationPoint_ withResult:TouchCalibrationResult_MultipleTouchesDetected];
    }
    [self setAppropriateStateBecauseCalibrationFinished];
}

- (void)computeTouchedRays:(vector<BOOL> &)rayWasTouched {
    NSUInteger l = MIN(touchDistanceSums_.size(), untouchedFieldDistances_.size());
    rayWasTouched.clear();
    rayWasTouched.reserve(l);
    for (NSUInteger i = 0; i < l; ++i) {
        BOOL wasTouched = NO;
        if (touchDistanceCounts_[i] >= kDistancesNeededForRayToBeTreatedAsTouch) {
            Lidar2DDistance averageDistance = touchDistanceSums_[i] / touchDistanceCounts_[i];
            if (averageDistance < untouchedFieldDistances_[i]) {
                wasTouched = YES;
            }
        }
        rayWasTouched.push_back(wasTouched);
    }
}

- (void)forEachSweepInTouchedRays:(vector<BOOL> const &)rayWasTouched do:(void (^)(NSUInteger middleRayIndex))block {
    NSUInteger i = 0;
    while (i < rayWasTouched.size()) {
        if (rayWasTouched[i]) {
            NSUInteger end = i + 1;
            while (end < rayWasTouched.size() && rayWasTouched[end]) {
                ++end;
            }
            block(i + (end - i) / 2);
            i = end;
        } else {
            ++i;
        }
    }
}

- (void)recordCalibratedTouchAtRayIndex:(NSUInteger)rayIndex{
    double distance = (double)touchDistanceSums_[rayIndex] / touchDistanceSums_[rayIndex];
    double radians = device_.coverageDegrees * rayIndex / (2 * M_PI * touchDistanceCounts_.size());
    sensorPointsForTouchCalibration_.push_back(SensorPoint(distance * cos(radians), distance * sin(radians)));
    screenPointsForTouchCalibration_.push_back(ScreenPoint(currentCalibrationPoint_.x, currentCalibrationPoint_.y));
    if (sensorPointsForTouchCalibration_.size() >= kTouchCalibrationsNeeded) {
        [self computeSensorToScreenTransform];
    }
}

- (void)computeSensorToScreenTransform {
    static char kTranspose = 'T'; // My matrices are stored row-major, so I need dgels_ to transpose them.
    vector<ScreenPoint> bx = screenPointsForTouchCalibration_;
    __CLPK_integer m = (__CLPK_integer)sensorPointsForTouchCalibration_.size();
    __CLPK_integer n = 3;
    __CLPK_integer nrhs = 2;
    __CLPK_integer lda = sizeof(sensorPointsForTouchCalibration_[0]) / sizeof(sensorPointsForTouchCalibration_[0].x);
    __CLPK_integer ldb = sizeof(bx[0]) / sizeof(bx[0].x);
    __CLPK_doublereal work_fixed[1];
    __CLPK_integer lwork = -1;
    __CLPK_integer info;

    // First, we ask dgels_ how much work area it needs.
    dgels_(&kTranspose, &m, &n, &nrhs, &sensorPointsForTouchCalibration_[0].x, &lda, &bx[0].x, &ldb, work_fixed, &lwork, &info);

    if (info != 0) {
        [NSException raise:NSInternalInconsistencyException format:@"dgels_ failed to compute workspace size: info=%d", info];
    }

    // Now we can allocate the workspace.
    lwork = (__CLPK_integer)work_fixed[0];
    __CLPK_doublereal *work = (__CLPK_doublereal *)malloc(sizeof(__CLPK_doublereal) * lwork);

    // This time, we ask dgels_ to solve the linear least squares problem.
    dgels_(&kTranspose, &m, &n, &nrhs, &sensorPointsForTouchCalibration_[0].x, &lda, &bx[0].x, &ldb, work, &lwork, &info);
    free(work);

    if (info != 0) {
        [NSException raise:NSInternalInconsistencyException format:@"dgels_ failed to compute transform: info=%d", info];
    }

    sensorToScreenTransform_ = (CGAffineTransform){
        .a = bx[0].x, .b = bx[0].y,
        .c = bx[1].x, .d = bx[1].y,
        .tx = bx[2].x, .ty = bx[2].y
    };
}

@end
