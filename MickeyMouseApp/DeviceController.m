//
//  DeviceController.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "DeviceController.h"
#import "RawDataGraphView.h"
#import "MyWindow.h"
#import "Lidar2D.h"

@interface DeviceController ()

@end

@implementation DeviceController {
    DeviceController *myself_; // set to self while window is ordered in to avoid being deallocated
    Lidar2D *device_;
    id windowWillOrderInObserver_;
    id windowWillCloseObserver_;
    IBOutlet NSTextField *statusField_;
    IBOutlet RawDataGraphView *graphView_;
    volatile BOOL wantsStreamingData_;

    NSUInteger rayCount_;
    uint32_t *untouchedRayDistances_;
}

#pragma mark - Public API

- (id)initWithLidar2D:(Lidar2D *)device {
    if (self = [super initWithWindowNibName:@"DeviceController"]) {
        device_ = device;
    }
    return self;
}

- (void)dealloc {
    [self stopObservingWindowPresence];
    [self stopStreamingData];
}

#pragma mark - NSWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    __block NSString *serialNumber;
    [proxy_ performBlockAndWait:^(id<Lidar2D> device) {
        serialNumber = device.serialNumber;
    }];
    self.window.title = [NSString stringWithFormat:@"Lidar2D %@", serialNumber];
    statusField_.stringValue = @"Loading";
    [self startObservingWindowPresence];
}

#pragma mark - Implementation details

- (void)startObservingWindowPresence {
    __unsafe_unretained DeviceController *me = self;
    windowWillOrderInObserver_ = [[NSNotificationCenter defaultCenter] addObserverForName:MyWindowWillOrderInNotification object:self.window queue:nil usingBlock:^(NSNotification *note) {
        (void)note;
        [me windowWillBecomePresent];
    }];
    windowWillCloseObserver_ = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:self.window queue:nil usingBlock:^(NSNotification *note) {
        (void)note;
        [me windowWillBecomeAbsent];
    }];
}

- (void)stopObservingWindowPresence {
    if (windowWillOrderInObserver_) {
        [[NSNotificationCenter defaultCenter] removeObserver:windowWillOrderInObserver_];
        windowWillOrderInObserver_ = nil;
    }
    if (windowWillCloseObserver_) {
        [[NSNotificationCenter defaultCenter] removeObserver:windowWillCloseObserver_];
        windowWillCloseObserver_ =nil;
    }
}

- (void)windowWillBecomePresent {
    myself_ = self;
    [self startStreamingData];
}

- (void)windowWillBecomeAbsent {
    myself_ = nil;
    [self stopStreamingData];
}

- (void)startStreamingData {
    wantsStreamingData_ = YES;

    [proxy_ performBlock:^(id<Lidar2D> device) {
        [self updateStatusLabelIfNecessaryAndClearErrorWithDevice:device];

        [self setStatusLabelText:@"Preparing to calibrate - REMOVE ALL OBSTRUCTIONS FROM SCREEN"];
        [self resetUntouchedRayDistancesWithDevice:device];
        sleep(1);
        [self setStatusLabelText:@"Calibrating - DO NOT OBSTRUCT SCREEN"];
        __block int calibrationFramesLeft = 20;
        while (calibrationFramesLeft > 0) {
            [device forEachStreamingDataSnapshot:^(uint32_t const *distances, BOOL *stop) {
                if (device.error) {
                    NSLog(@"error during calibration: %@", device.error);
                    device.error = nil;
                    return;
                }
                
                [self setStatusLabelText:[NSString stringWithFormat:@"Calibrating %d - DO NOT OBSTRUCT SCREEN", calibrationFramesLeft]];
                [self updateUntouchedRayDistancesWithDevice:device distances:distances];
                dispatch_async(dispatch_get_main_queue(), ^{
                    graphView_.data = [NSData dataWithBytes:distances length:rayCount_ * sizeof *distances];
                });
                *stop = (--calibrationFramesLeft < 1);
            }];
        }

        [self setStatusLabelText:@"Calibration finished"];
        
        [self finalizeUntouchedRayDistancesWithDevice:device];

        dispatch_async(dispatch_get_main_queue(), ^{
            graphView_.untouchedDistances = [NSData dataWithBytes:untouchedRayDistances_ length:rayCount_ * sizeof *untouchedRayDistances_];
        });

        while (wantsStreamingData_) {
            [self setStatusLabelText:@"Requesting streaming data"];
            [device forEachStreamingDataSnapshot:^(uint32_t const *distances, BOOL *stop) {
                [self setStatusLabelText:@"Received streaming data"];
                dispatch_async(dispatch_get_main_queue(), ^{
                    graphView_.data = [NSData dataWithBytes:distances length:rayCount_ * sizeof *distances];
                });
                *stop = !wantsStreamingData_;
            }];

            NSError *error = device.error;
            [self updateStatusLabelIfNecessaryAndClearErrorWithDevice:device];
            if (error) {
                if (wantsStreamingData_) {
                    sleep(1);
                }
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    statusField_.stringValue = @"Streaming data stopped";
                });
            }
        }
    }];
}

- (void)setStatusLabelText:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        statusField_.stringValue = text;
    });
}

- (void)updateStatusLabelIfNecessaryAndClearErrorWithDevice:(id<Lidar2D>) device {
    NSError *error = device.error;
    if (error) {
        [self setStatusLabelText:@"Device Error"];
        NSLog(@"device error: %@", device.error);
        device.error = nil;
    }
}

- (void)stopStreamingData {
    wantsStreamingData_ = NO;
}

- (void)resetUntouchedRayDistancesWithDevice:(id<Lidar2D>)device {
    (void)device; // only passed to ensure I'm run on the device's queue
    if (rayCount_ == 0) {
        rayCount_ = device.rayCount;
        untouchedRayDistances_ = malloc(rayCount_ * sizeof *untouchedRayDistances_);
    }

    for (size_t i = 0; i < rayCount_; ++i) {
        untouchedRayDistances_[i] = UINT32_MAX;
    }
}

- (void)updateUntouchedRayDistancesWithDevice:(id<Lidar2D>)device distances:(uint32_t const *)distances {
    (void)device; // only passed to ensure I'm run on the device's queue
    for (size_t i = 0; i < rayCount_; ++i) {
        uint32_t distance = distances[i];
        if (distance >= 20 && distance < untouchedRayDistances_[i]) {
            untouchedRayDistances_[i] = distance;
        }
    }
}

- (void)finalizeUntouchedRayDistancesWithDevice:(id<Lidar2D>)device {
    (void)device; // only passed to ensure I'm run on the device's queue
    for (size_t i = 0; i < rayCount_; ++i) {
        untouchedRayDistances_[i] *= 0.95;
    }
}

@end
