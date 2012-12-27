//
//  TouchThresholdCalibration.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/26/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "NSData+Lidar2D.h"
#import "TouchThresholdCalibration.h"
#import <vector>

using std::vector;

static NSUInteger const kReportsNeeded = 20;

@interface TouchThresholdCalibration ()

// Use a property to make it KVO compliant.
@property (nonatomic, readwrite) BOOL ready;

@end

@implementation TouchThresholdCalibration {
    vector<Lidar2DDistance> thresholdDistances_;
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
        [self resetThresholdDistancesWithCount:data.lidar2D_distanceCount];
    }
    [self updateThresholdDistancesWithDistanceData:data];
    ++reportsReceived_;
    [self becomeReadyIfPossible];
}

- (void)forEachTouchedSweepInDistanceData:(NSData *)data do:(void (^)(NSRange))block {
    NSUInteger count = MIN(data.lidar2D_distanceCount, thresholdDistances_.size());
    Lidar2DDistance const *distances = data.lidar2D_distances;
    NSUInteger begin = 0;
    while (begin < count) {
        if (distances[begin] < thresholdDistances_[begin]) {
            NSUInteger end = begin + 1;
            while (end < count && distances[end] < thresholdDistances_[end]) {
                ++end;
            }
            block(NSMakeRange(begin, end - begin));
            begin = end;
        } else {
            ++begin;
        }
    }
}

- (void)getTouchThresholdDistancesWithBlock:(void (^)(Lidar2DDistance const *distances, NSUInteger count))block {
    block(thresholdDistances_.data(), thresholdDistances_.size());
}

#pragma mark - Implementation details

- (void)resetThresholdDistancesWithCount:(NSUInteger)count {
    thresholdDistances_.assign(count, Lidar2DDistance_Invalid);
}

- (void)updateThresholdDistancesWithDistanceData:(NSData *)distanceData {
    Lidar2DDistance const *distances = distanceData.lidar2D_distances;
    NSUInteger count = MIN(distanceData.lidar2D_distanceCount, thresholdDistances_.size());
    if (count < thresholdDistances_.size()) {
        thresholdDistances_.resize(count);
    }
    for (NSUInteger i = 0; i < count; ++i) {
        thresholdDistances_[i] = MIN(thresholdDistances_[i], distances[i]);
    }
}

- (void)becomeReadyIfPossible {
    if (reportsReceived_ < kReportsNeeded)
        return;
    if (_ready) {
        [NSException raise:NSInternalInconsistencyException format:@"%@ received too many reports", self];
    }
    [self tweakThresholdDistances];
    self.ready = YES; // Use accessor for KVO
}

- (void)tweakThresholdDistances {
    for (auto p = thresholdDistances_.begin(); p != thresholdDistances_.end(); ++p) {
        *p *= 0.95f;
    }
}

@end
