//
//  TouchCalibration.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/27/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "TouchCalibration.h"
#import "TouchThresholdCalibration.h"
#import <vector>

using std::vector;

static NSUInteger const kTouchesNeeded = 3;
static NSUInteger const kReportsNeeded = 20;
static NSUInteger const kDistancesNeededForRayToBeTreatedAsTouch = kReportsNeeded;

@interface TouchCalibration ()
// Use a property for KVO compliance.
@property (nonatomic, readwrite) BOOL ready;
@end

@implementation TouchCalibration {
    
    CGPoint currentScreenPoint_;

    NSUInteger reportsReceived_;

    // Each element of `touchDistanceSums_` corresponds to one ray and is the sum of the valid distances reported for that ray since I started calibrating the current touch.
    vector<Lidar2DDistance> distanceSums_;

    // Each element of `touchDistanceCounts_` corresponds to one ray and is the number of valid distances reported for that ray since I started calibrating the current touch.
    vector<uint16_t> distanceCounts_;

    vector<CGPoint> sensorPoints_;
    vector<CGPoint> screenPoints_;

    CGAffineTransform transform_;
}

#pragma mark - Package API

@synthesize delegate = _delegate;
@synthesize thresholdCalibration = _thresholdCalibration;
@synthesize radiansPerRay = _radiansPerRay;
@synthesize ready = _ready;

- (void)reset {
    sensorPoints_.clear();
    screenPoints_.clear();
    reportsReceived_ = 0;
    self.ready = NO;
}

- (void)startCalibratingTouchAtScreenPoint:(CGPoint)screenPoint {
    currentScreenPoint_ = screenPoint;
}

- (void)calibrateWithDistanceData:(NSData *)data {
    if (reportsReceived_ == 0) {
        [self resetTouchDistanceDataWithCount:data.lidar2D_distanceCount];
    }
    [self updateTouchDistancesWithDistanceData:data];
    ++reportsReceived_;
    [self finishCalibratingTouchIfPossible];
}

- (CGPoint)screenPointForRayIndex:(NSUInteger)rayIndex distance:(Lidar2DDistance)distance {
    CGPoint sensorPoint = [self sensorPointForRayIndex:rayIndex distance:distance];
    return CGPointApplyAffineTransform(sensorPoint, transform_);
}

#pragma mark - Implementation details

- (void)resetTouchDistanceDataWithCount:(NSUInteger)count {
    distanceSums_.assign(count, 0);
    distanceCounts_.assign(count, 0);
    reportsReceived_ = 0;
}

- (void)updateTouchDistancesWithDistanceData:(NSData *)data {
    NSUInteger count = MIN(data.lidar2D_distanceCount, distanceCounts_.size());
    if (count < distanceCounts_.size()) {
        distanceCounts_.resize(count);
        distanceSums_.resize(count);
    }
    Lidar2DDistance const *distances = data.lidar2D_distances;

    for (NSUInteger i = 0; i < count; ++i) {
        Lidar2DDistance distance = distances[i];
        if (distance == Lidar2DDistance_Invalid)
            continue;
        distanceSums_[i] += distance;
        ++distanceCounts_[i];
    }
}

- (void)finishCalibratingTouchIfPossible {
    if (reportsReceived_ < kReportsNeeded)
        return;
    TouchCalibrationResult result = [self addCalibratedPointIfPossible];
    [_delegate didFinishCalibrationWithResult:result];
    [self becomeReadyIfPossible];
}

- (TouchCalibrationResult)addCalibratedPointIfPossible {
    vector<Lidar2DDistance> averages;
    [self getAverageDistances:averages];
    NSData *averageData = [[NSData alloc] initWithBytes:averages.data() length:averages.size() * sizeof averages[0]];
    __block NSUInteger touchesFound = 0;
    __block NSUInteger rayIndex;
    [_thresholdCalibration forEachTouchedSweepInDistanceData:averageData do:^(NSRange sweepRange) {
        ++touchesFound;
        rayIndex = sweepRange.location + sweepRange.length / 2;
    }];

    if (touchesFound == 0)
        return TouchCalibrationResult_NoTouchDetected;
    else if (touchesFound > 1)
        return TouchCalibrationResult_MultipleTouchesDetected;

    [self recordTouchAtRayIndex:rayIndex distance:averages[rayIndex]];
    return TouchCalibrationResult_Success;
}

- (void)getAverageDistances:(vector<Lidar2DDistance> &)averages {
    NSUInteger count = distanceSums_.size();
    averages.reserve(count);
    for (NSUInteger i = 0; i < count; ++i) {
        Lidar2DDistance distance = (distanceCounts_[i] >= kDistancesNeededForRayToBeTreatedAsTouch)
            ? distanceSums_[i] / distanceCounts_[i]
            : Lidar2DDistance_Invalid;
        averages.push_back(distance);
    }
}

- (void)recordTouchAtRayIndex:(NSUInteger)rayIndex distance:(Lidar2DDistance)distance {
    sensorPoints_.push_back([self sensorPointForRayIndex:rayIndex distance:distance]);
    screenPoints_.push_back(CGPointMake(currentScreenPoint_.x, currentScreenPoint_.y));
}

- (CGPoint)sensorPointForRayIndex:(NSUInteger)rayIndex distance:(Lidar2DDistance)distance {
    double radians = rayIndex * _radiansPerRay;
    return CGPointMake(distance * cos(radians), distance * sin(radians));
}

- (void)becomeReadyIfPossible {
    if (sensorPoints_.size() < kTouchesNeeded)
        return;
    [self computeTransform];
    self.ready = YES;
}

- (void)computeTransform {
    static char kNoTranspose = 'N';

    // LAPACK on Mac only supports column-major order.

    size_t sampleCount = sensorPoints_.size();
    
    vector<__CLPK_doublereal> a(sampleCount * 3);
    for (size_t i = 0; i < sampleCount; ++i) {
        a[i] = sensorPoints_[i].x;
        a[sampleCount + i] = sensorPoints_[i].y;
        a[2 * sampleCount + i] = 1;
    }

    vector<__CLPK_doublereal> bx(sampleCount * 2);
    for (size_t i = 0; i < sampleCount; ++i) {
        bx[i] = screenPoints_[i].x;
        bx[sampleCount + i] = screenPoints_[i].y;
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

    transform_ = (CGAffineTransform){
        .a = bx[0], .b = bx[sampleCount + 0],
        .c = bx[1], .d = bx[sampleCount + 1],
        .tx = bx[2], .ty = bx[sampleCount + 2]
    };
}

@end
