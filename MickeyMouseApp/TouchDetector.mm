//  Copyright (c) 2012 Rob Mayoff. All rights reserved.

#import "DqdObserverSet.h"
#import "Lidar2D.h"
#import "TouchDetector.h"
#import <vector>

using std::vector;

static Lidar2DDistance const kMinimumDistance = 20;
static Lidar2DDistance const kMaximumDistance = 5600;
static NSUInteger const kReportsNeededForUntouchedFieldCalibration = 20;
static NSUInteger const kTouchCalibrationsNeeded = 3;
static NSUInteger const kReportsNeededForTouchCalibration = 20;
static NSUInteger const kDistancesNeededForRayToBeTreatedAsTouch = 15;

static BOOL isValidDistance(Lidar2DDistance distance) {
    return distance >= kMinimumDistance && distance <= kMaximumDistance;
}

static Lidar2DDistance correctedDistance(Lidar2DDistance distance) {
    return isValidDistance(distance) ? distance : Lidar2DDistance_MAX;
}

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

    vector<CGPoint> sensorPointsForTouchCalibration_;
    vector<CGPoint> screenPointsForTouchCalibration_;
    
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
    TouchDetectorState newState = [self needsUntouchedFieldCalibration] ? TouchDetectorState_AwaitingUntouchedFieldCalibration
        : [self needsTouchCalibration] ? TouchDetectorState_AwaitingTouchCalibration
        : TouchDetectorState_DetectingTouches;
    if (newState != _state) {
        self.state = newState;
        if (newState == TouchDetectorState_DetectingTouches) {
            [self startDetectingTouches];
        }
    }
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
#undef StateString
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
        *p *= 0.90;
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
    distancesReportHandler_ = nil;

    vector<BOOL> rayWasTouched;
    [self computeTouchedRaysForCalibration:rayWasTouched];
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

- (void)computeTouchedRaysForCalibration:(vector<BOOL> &)rayWasTouched {
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

- (void)recordCalibratedTouchAtRayIndex:(NSUInteger)rayIndex{
    double distance = (double)touchDistanceSums_[rayIndex] / touchDistanceCounts_[rayIndex];
    sensorPointsForTouchCalibration_.push_back([self sensorPointForRayIndex:rayIndex distance:distance]);
    screenPointsForTouchCalibration_.push_back(CGPointMake(currentCalibrationPoint_.x, currentCalibrationPoint_.y));
    if (sensorPointsForTouchCalibration_.size() >= kTouchCalibrationsNeeded) {
        [self computeSensorToScreenTransform];
    }
}

- (void)computeSensorToScreenTransform {
    static char kNoTranspose = 'N';

    // LAPACK on Mac only supports column-major order.

    size_t sampleCount = sensorPointsForTouchCalibration_.size();
    
    vector<__CLPK_doublereal> a(sampleCount * 3);
    for (size_t i = 0; i < sampleCount; ++i) {
        a[i] = sensorPointsForTouchCalibration_[i].x;
        a[sampleCount + i] = sensorPointsForTouchCalibration_[i].y;
        a[2 * sampleCount + i] = 1;
    }

    vector<__CLPK_doublereal> bx(sampleCount * 2);
    for (size_t i = 0; i < sampleCount; ++i) {
        bx[i] = screenPointsForTouchCalibration_[i].x;
        bx[sampleCount + i] = screenPointsForTouchCalibration_[i].y;
    }

    __CLPK_integer m = (__CLPK_integer)sampleCount;
    __CLPK_integer n = 3;
    __CLPK_integer nrhs = 2;
    __CLPK_integer lda = m;
    __CLPK_integer ldb = m;
    __CLPK_doublereal work_fixed[1];
    __CLPK_integer lwork = -1;
    __CLPK_integer info;

    // First, we ask dgels_ how much work area it needs.
    dgels_(&kNoTranspose, &m, &n, &nrhs, a.data(), &lda, bx.data(), &ldb, work_fixed, &lwork, &info);

    if (info != 0) {
        [NSException raise:NSInternalInconsistencyException format:@"dgels_ failed to compute workspace size: info=%d", info];
    }

    // Now we can allocate the workspace.
    lwork = (__CLPK_integer)work_fixed[0];
    __CLPK_doublereal *work = (__CLPK_doublereal *)malloc(sizeof(__CLPK_doublereal) * lwork);

    // This time, we ask dgels_ to solve the linear least squares problem.
    dgels_(&kNoTranspose, &m, &n, &nrhs, a.data(), &lda, bx.data(), &ldb, work, &lwork, &info);
    free(work);

    if (info != 0) {
        [NSException raise:NSInternalInconsistencyException format:@"dgels_ failed to compute transform: info=%d", info];
    }

    sensorToScreenTransform_ = (CGAffineTransform){
        .a = bx[0], .b = bx[sampleCount + 0],
        .c = bx[1], .d = bx[sampleCount + 1],
        .tx = bx[2], .ty = bx[sampleCount + 2]
    };
}

#pragma mark - Touch detection details

static BOOL isValidScreenPoint(CGPoint point) {
    for (NSScreen *screen in [NSScreen screens]) {
        if (CGRectContainsPoint(screen.frame, point))
            return YES;
    }
    return NO;
}

- (void)detectTouchesWithDistances:(Lidar2DDistance const *)distances {
    vector<BOOL> rayWasTouched;
    [self computeTouchedRays:rayWasTouched forDetectionWithDistances:distances];
    __block vector<CGPoint> touchPoints;
    [self forEachSweepInTouchedRays:rayWasTouched do:^(NSUInteger middleRayIndex) {
        Lidar2DDistance distance = distances[middleRayIndex];
        CGPoint sensorPoint = [self sensorPointForRayIndex:middleRayIndex distance:distance];
        CGPoint screenPoint = [self screenPointForSensorPoint:sensorPoint];
        if (isValidScreenPoint(screenPoint)) {
            touchPoints.push_back(screenPoint);
        }
    }];
    if (touchPoints.size() > 0) {
        [observers_.proxy touchDetector:self didDetectTouches:touchPoints.size() atScreenPoints:touchPoints.data()];
    }
}

- (void)computeTouchedRays:(vector<BOOL> &)rayWasTouched forDetectionWithDistances:(Lidar2DDistance const *)distances {
    NSUInteger count = MIN(device_.rayCount, untouchedFieldDistances_.size());
    rayWasTouched.clear();
    rayWasTouched.reserve(count);
    for (NSUInteger i = 0; i < count; ++i) {
        Lidar2DDistance distance = correctedDistance(distances[i]);
        rayWasTouched.push_back(distance < untouchedFieldDistances_[i]);
    }
}

- (void)startDetectingTouches {
    self.state = TouchDetectorState_DetectingTouches;

    __weak TouchDetector *me = self;
    distancesReportHandler_ = ^(Lidar2DDistance const *distances) {
        [me detectTouchesWithDistances:distances];
    };
}

#pragma mark - Implementation details

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

- (CGPoint)sensorPointForRayIndex:(NSUInteger)rayIndex distance:(Lidar2DDistance)distance {
    double radians = (2.0 * M_PI / 360.0) * (device_.firstRayOffsetDegrees + device_.coverageDegrees * (double)rayIndex / touchDistanceCounts_.size());
    return CGPointMake(distance * cos(radians), distance * sin(radians));
}

- (CGPoint)screenPointForSensorPoint:(CGPoint)sensorPoint {
    return CGPointApplyAffineTransform(sensorPoint, sensorToScreenTransform_);
}

@end
