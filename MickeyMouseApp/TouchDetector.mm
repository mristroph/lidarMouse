//  Copyright (c) 2012 Rob Mayoff. All rights reserved.

#import "DqdObserverSet.h"
#import "Lidar2D.h"
#import "NSData+Lidar2D.h"
#import "TouchDetector.h"
#import "UntouchedFieldCalibration.h"
#import <vector>

using std::vector;

static NSUInteger const kReportsNeededForUntouchedFieldCalibration = 20;
static NSUInteger const kTouchCalibrationsNeeded = 3;
static NSUInteger const kReportsNeededForTouchCalibration = 20;
static NSUInteger const kDistancesNeededForRayToBeTreatedAsTouch = kReportsNeededForTouchCalibration;

@interface TouchDetector () <Lidar2DObserver>
@end

@implementation TouchDetector {
    Lidar2D *device_;
    DqdObserverSet *observers_;
    void (^distancesReportHandler_)(NSData *distanceData);
    UntouchedFieldCalibration *untouchedFieldCalibration_;

    // Each element of `touchDistanceSums_` corresponds to one ray and is the sum of the valid distances reported for that ray since I started calibrating the current touch.
    vector<Lidar2DDistance> touchDistanceSums_;

    // Each element of `touchDistanceCounts_` corresponds to one ray and is the number of valid distances reported for that ray since I started calibrating the current touch.
    vector<uint16_t> touchDistanceCounts_;

    NSUInteger reportsReceivedForTouchCalibration_;

    vector<CGPoint> sensorPointsForTouchCalibration_;
    vector<CGPoint> screenPointsForTouchCalibration_;
    
    CGPoint currentCalibrationPoint_;
    
    Lidar2DDistance touchDistance_;
    
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
        untouchedFieldCalibration_ = [[UntouchedFieldCalibration alloc] init];
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
    [untouchedFieldCalibration_ reset];
    self.state = TouchDetectorState_CalibratingUntouchedField;

    __weak TouchDetector *me = self;
    distancesReportHandler_ = ^(NSData *distanceData) {
        TouchDetector *self = me;
        [self calibrateUntouchedFieldWithDistanceData:distanceData];
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
    distancesReportHandler_ = ^(NSData *distanceData) {
        [me calibrateTouchWithDistanceData:distanceData];
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

- (void)getUntouchedFieldDistancesWithBlock:(void (^)(Lidar2DDistance const *, NSUInteger))block {
    [untouchedFieldCalibration_ getUntouchedFieldDistancesWithBlock:block];
}

#pragma mark - Lidar2DObserver protocol

-  (void)lidar2DDidTerminate:(Lidar2D *)device {
    (void)device;
    // Nothing to do
}

- (void)lidar2d:(Lidar2D *)device didReceiveDistanceData:(NSData *)distanceData {
    (void)device;
    if (distancesReportHandler_) {
        distancesReportHandler_(distanceData);
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
    return !untouchedFieldCalibration_.ready;
}

- (void)calibrateUntouchedFieldWithDistanceData:(NSData *)distanceData {
    [untouchedFieldCalibration_ calibrateWithDistanceData:distanceData];
    [self stopCalibratingUntouchedFieldIfReady];
}

- (void)stopCalibratingUntouchedFieldIfReady {
    if (untouchedFieldCalibration_.ready) {
        distancesReportHandler_ = nil;
        [observers_.proxy touchDetectorDidFinishCalibratingUntouchedField:self];
        [self setAppropriateStateBecauseCalibrationFinished];
    }
}

#pragma mark - Touch calibration details

- (BOOL)needsTouchCalibration {
    return sensorPointsForTouchCalibration_.size() < kTouchCalibrationsNeeded;
}

- (void)calibrateTouchWithDistanceData:(NSData *)distanceData {
    if (reportsReceivedForTouchCalibration_ == 0) {
        [self resetTouchDistanceSums];
    } else if (reportsReceivedForTouchCalibration_ == kReportsNeededForTouchCalibration) {
        [NSException raise:NSInternalInconsistencyException format:@"%s called with reportsReceivedForTouchCalibration_ == %ld == kReportsNeededForUntouchedFieldCalibration", __func__, reportsReceivedForTouchCalibration_];
    }

    [self updateTouchDistancesWithReportedDistanceData:distanceData];
    [self updateReportsReceivedForTouchCalibration];
}

- (void)resetTouchDistanceSums {
    NSUInteger count = device_.rayCount;
    touchDistanceSums_.assign(count, 0);
    touchDistanceCounts_.assign(count, 0);
}

- (void)updateTouchDistancesWithReportedDistanceData:(NSData *)distanceData {
    NSUInteger l = MIN(touchDistanceSums_.size(), distanceData.lidar2D_distanceCount);
    Lidar2DDistance const *distances = distanceData.lidar2D_distances;
    for (NSUInteger i = 0; i < l; ++i) {
        Lidar2DDistance distance = distances[i];
        if (isLidar2DDistanceValid(distance)) {
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
    NSData *averageDistanceData = [self touchCalibrationAverageDistanceData];
    __block NSUInteger touchesFound = 0;
    __block NSUInteger rayIndex;
    // Here I rely on Lidar2DDistance_Invalid being very large.
    [untouchedFieldCalibration_ forEachTouchedSweepInDistanceData:averageDistanceData do:^(NSRange sweepRange) {
        ++touchesFound;
        rayIndex = sweepRange.location + sweepRange.length / 2;
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

- (NSData *)touchCalibrationAverageDistanceData {
    vector<Lidar2DDistance> averages;
    NSUInteger count = touchDistanceSums_.size();
    averages.reserve(count);
    for (NSUInteger i = 0; i < count; ++i) {
        Lidar2DDistance distance = (touchDistanceCounts_[i] >= kDistancesNeededForRayToBeTreatedAsTouch)
            ? touchDistanceSums_[i] / touchDistanceCounts_[i]
            : Lidar2DDistance_Invalid;
        averages.push_back(distance);
    }
    return [NSData dataWithBytes:averages.data() length:count * sizeof averages[0]];
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

- (void)detectTouchesWithDistanceData:(NSData *)distanceData {
    __block vector<CGPoint> touchPoints;
    Lidar2DDistance const *distances = distanceData.lidar2D_distances;

#if 0

    [untouchedFieldCalibration_ forEachTouchedSweepInDistanceData:distanceData do:^(NSRange sweepRange) {
        NSUInteger middleRayIndex = sweepRange.location + sweepRange.length / 2;
        Lidar2DDistance distance = distances[middleRayIndex];
        CGPoint sensorPoint = [self sensorPointForRayIndex:middleRayIndex distance:distance];
        CGPoint screenPoint = [self screenPointForSensorPoint:sensorPoint];
        if (isValidScreenPoint(screenPoint)) {
            touchPoints.push_back(screenPoint);
        }
    }];

#else

    // Alternative implementation. Only accepts touches with at least 3 consecutive touched rays; uses angle of middle ray and averaged distance of all rays except first and last.
    float currentDistanceWeight = 0.3;
    [untouchedFieldCalibration_ forEachTouchedSweepInDistanceData:distanceData do:^(NSRange sweepRange) {
        if (sweepRange.length < 3)
            return;
        ++sweepRange.location;
        sweepRange.length -= 2;
        Lidar2DDistance sum = 0;
        for (NSUInteger i = 0; i < sweepRange.length; ++i) {
            sum += distances[sweepRange.location + i];
        }
        
        NSUInteger middleRayIndex = sweepRange.location + sweepRange.length / 2;
        Lidar2DDistance currentDistance = sum / sweepRange.length;
        touchDistance_ = (touchDistance_ > 0)
            ? currentDistanceWeight * currentDistance + (1.0 - currentDistanceWeight) * touchDistance_
            : currentDistance;

        CGPoint sensorPoint = [self sensorPointForRayIndex:middleRayIndex distance:touchDistance_];
        CGPoint screenPoint = [self screenPointForSensorPoint:sensorPoint];
        if (isValidScreenPoint(screenPoint)) {
            touchPoints.push_back(screenPoint);
        }
    }];

    if(touchPoints.size() == 0) {
        touchDistance_ = -1.0;
    }

#endif

    [observers_.proxy touchDetector:self didDetectTouches:touchPoints.size() atScreenPoints:touchPoints.data()];
}

- (void)startDetectingTouches {
    self.state = TouchDetectorState_DetectingTouches;

    __weak TouchDetector *me = self;
    distancesReportHandler_ = ^(NSData *distanceData) {
        [me detectTouchesWithDistanceData:distanceData];
    };
}

#pragma mark - Implementation details

- (CGPoint)sensorPointForRayIndex:(NSUInteger)rayIndex distance:(Lidar2DDistance)distance {
    double radians = (2.0 * M_PI / 360.0) * (device_.firstRayOffsetDegrees + device_.coverageDegrees * (double)rayIndex / touchDistanceCounts_.size());
    return CGPointMake(distance * cos(radians), distance * sin(radians));
}

- (CGPoint)screenPointForSensorPoint:(CGPoint)sensorPoint {
    return CGPointApplyAffineTransform(sensorPoint, sensorToScreenTransform_);
}

@end
