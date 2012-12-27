//
//  UntouchedFieldCalibration.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/26/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "NSData+Lidar2D.h"
#import "UntouchedFieldCalibration.h"
#import <vector>

using std::vector;

static NSUInteger const kReportsNeeded = 20;

@interface UntouchedFieldCalibration ()

// Use a property to make it KVO compliant.
@property (nonatomic, readwrite) BOOL ready;

@end

@implementation UntouchedFieldCalibration {
    vector<Lidar2DDistance> untouchedDistances_;
    NSUInteger reportsReceived_;
}

#pragma mark - Package API

@synthesize ready = _ready;

- (void)reset {
    reportsReceived_ = 0;
    self.ready = NO;
}

- (void)calibrateWithDistanceData:(NSData *)data {
    if (reportsReceived_ == 0) {
        [self resetUntouchedDistancesWithCount:data.lidar2D_distanceCount];
    }
    [self updateUntouchedDistancesWithDistanceData:data];
    ++reportsReceived_;
    [self becomeReadyIfNeeded];
}

- (void)forEachTouchedSweepInDistanceData:(NSData *)data do:(void (^)(NSRange))block {
    NSUInteger count = MIN(data.lidar2D_distanceCount, untouchedDistances_.size());
    Lidar2DDistance const *distances = data.lidar2D_distances;
    NSUInteger begin = 0;
    while (begin < count) {
        if (distances[begin] < untouchedDistances_[begin]) {
            NSUInteger end = begin + 1;
            while (end < count && distances[end] < untouchedDistances_[end]) {
                ++end;
            }
            block(NSMakeRange(begin, end - begin));
        } else {
            ++begin;
        }
    }
}

- (void)getUntouchedFieldDistancesWithBlock:(void (^)(Lidar2DDistance const *distances, NSUInteger count))block {
    block(untouchedDistances_.data(), untouchedDistances_.size());
}

#pragma mark - Implementation details

- (void)resetUntouchedDistancesWithCount:(NSUInteger)count {
    untouchedDistances_.assign(count, 0);
}

- (void)updateUntouchedDistancesWithDistanceData:(NSData *)distanceData {
    Lidar2DDistance const *distances = distanceData.lidar2D_distances;
    NSUInteger count = MIN(distanceData.lidar2D_distanceCount, untouchedDistances_.size());
    if (count < untouchedDistances_.size()) {
        untouchedDistances_.resize(count);
    }
    for (NSUInteger i = 0; i < count; ++i) {
        untouchedDistances_[i] = MIN(untouchedDistances_[i], distances[i]);
    }
}

- (void)becomeReadyIfNeeded {
    if (reportsReceived_ < kReportsNeeded)
        return;
    if (_ready) {
        [NSException raise:NSInternalInconsistencyException format:@"%@ received too many reports", self];
    }
    [self tweakUntouchedDistances];
    self.ready = YES; // Use accessor for KVO
}

- (void)tweakUntouchedDistances {
    for (auto p = untouchedDistances_.begin(); p != untouchedDistances_.end(); ++p) {
        *p *= 0.90f;
    }
}

@end
